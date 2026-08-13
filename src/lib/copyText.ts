/**
 * Copying text to the clipboard, without letting it take the app down.
 *
 * `import * as Clipboard from "expo-clipboard"` is evaluated the moment any
 * screen that uses it is loaded, and it throws outright when the native module
 * is missing from the binary. That turns "copy does not work" into "the app
 * shows a red screen and never starts" — which is what happened here after the
 * module was added to package.json but had not reached the built app yet.
 *
 * Requiring it lazily, inside a try, keeps the failure the size of the feature.
 */
type ClipboardModule = {
  setStringAsync: (value: string) => Promise<boolean>;
};

let cached: ClipboardModule | null | undefined;

function loadClipboard(): ClipboardModule | null {
  if (cached !== undefined) return cached;
  try {
    const candidate = require("expo-clipboard") as unknown;
    const api = ((candidate as { default?: unknown })?.default ??
      candidate) as Partial<ClipboardModule> | undefined;
    cached = typeof api?.setStringAsync === "function"
      ? (api as ClipboardModule)
      : null;
  } catch {
    cached = null;
  }
  return cached;
}

/** True when the text was copied; false when this build cannot copy. */
export async function copyText(value: string): Promise<boolean> {
  const clipboard = loadClipboard();
  if (!clipboard) return false;
  try {
    await clipboard.setStringAsync(value);
    return true;
  } catch {
    return false;
  }
}
