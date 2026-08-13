/**
 * Crash and error reporting.
 *
 * There is no third-party service wired up yet, and adding one is a decision
 * about where a temple's data goes rather than a technical one. So this keeps
 * a small in-memory log a Tech Admin can read from the app, and exposes one
 * place to plug a real reporter into later — rather than scattering
 * `console.error` around and hoping somebody is watching Metro.
 */

export type CrashRecord = {
  id: string;
  message: string;
  stack?: string;
  componentStack?: string;
  context?: Record<string, unknown>;
  at: string;
};

type Reporter = (record: CrashRecord) => void;

const MAX_KEPT = 25;
const recent: CrashRecord[] = [];
let reporter: Reporter | null = null;
let counter = 0;

/**
 * Point this at Sentry, Bugsnag or an own endpoint when one is chosen:
 *   setCrashReporter((record) => Sentry.captureException(...))
 */
export function setCrashReporter(next: Reporter | null) {
  reporter = next;
}

export function reportCrash(
  error: unknown,
  context?: Record<string, unknown>,
) {
  counter += 1;
  const record: CrashRecord = {
    id: `crash-${counter}`,
    message:
      error instanceof Error
        ? error.message
        : typeof error === "string"
          ? error
          : "Unknown error",
    stack: error instanceof Error ? error.stack : undefined,
    componentStack:
      typeof context?.componentStack === "string"
        ? context.componentStack
        : undefined,
    context,
    at: new Date().toISOString(),
  };

  recent.unshift(record);
  if (recent.length > MAX_KEPT) recent.length = MAX_KEPT;

  if (__DEV__) {
    console.error("[crash]", record.message, record.stack ?? "");
  }
  try {
    reporter?.(record);
  } catch {
    // A failing reporter must never become the crash.
  }
  return record;
}

export function recentCrashes(): readonly CrashRecord[] {
  return recent;
}

export function clearCrashes() {
  recent.length = 0;
}
