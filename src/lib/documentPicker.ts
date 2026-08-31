/**
 * Picking a file off the device, without letting it take the app down.
 *
 * `await import("expo-document-picker")` looks lazy and is not: Metro compiles
 * a dynamic import into a synchronous `require` hoisted to module scope, so a
 * screen that only *might* pick a file still evaluates the native module the
 * moment the navigator that holds it is loaded. When the module is missing from
 * the built app — as it is in every binary older than the day the package was
 * added — that throws during startup, before React renders, and the app opens
 * on a blank screen with nothing on it to explain why.
 *
 * Requiring it lazily, inside a try, keeps the failure the size of the feature:
 * the calendar still displays, and only the upload button says it cannot run.
 *
 * Mirrors src/lib/copyText.ts, which exists for exactly this reason.
 */
export type PickedDocument = { uri: string; name: string | null };

type DocumentPickerModule = {
  getDocumentAsync: (options: {
    type?: string;
    copyToCacheDirectory?: boolean;
    multiple?: boolean;
  }) => Promise<{
    canceled: boolean;
    assets: Array<{ uri: string; name?: string | null }> | null;
  }>;
};

let cached: DocumentPickerModule | null | undefined;

function loadPicker(): DocumentPickerModule | null {
  if (cached !== undefined) return cached;
  try {
    const candidate = require("expo-document-picker") as unknown;
    const api = ((candidate as { default?: unknown })?.default ??
      candidate) as Partial<DocumentPickerModule> | undefined;
    cached =
      typeof api?.getDocumentAsync === "function"
        ? (api as DocumentPickerModule)
        : null;
  } catch {
    cached = null;
  }
  return cached;
}

/** True when this build can open the device's file picker at all. */
export function canPickDocuments(): boolean {
  return loadPicker() !== null;
}

/**
 * The file the devotee chose, or null when they cancelled.
 * Throws with a sentence worth showing when this build cannot pick files.
 */
export async function pickDocument(): Promise<PickedDocument | null> {
  const picker = loadPicker();
  if (!picker) {
    throw new Error(
      "This version of the app cannot open files yet. It needs the next app update before a calendar can be uploaded.",
    );
  }
  const result = await picker.getDocumentAsync({
    type: "*/*",
    copyToCacheDirectory: true,
    multiple: false,
  });
  if (result.canceled) return null;
  const asset = result.assets?.[0];
  if (!asset) return null;
  return { uri: asset.uri, name: asset.name ?? null };
}
