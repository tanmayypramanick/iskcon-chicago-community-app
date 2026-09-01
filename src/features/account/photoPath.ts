/**
 * The object path inside the devotee-photos bucket.
 *
 * Stored references have been written in two shapes over the app's life — a
 * full public URL and a bare path — so both are read here rather than
 * assuming whichever one this devotee happens to have.
 *
 * Kept apart from api.ts deliberately: that module reaches for the Supabase
 * client, which opens native storage the moment it is imported, and this is a
 * pure string function that a test should be able to call without any of that.
 */
export function photoPathIn(reference: string): string | null {
  const trimmed = reference.trim();
  if (!trimmed) return null;

  const marker = "/devotee-photos/";
  const at = trimmed.indexOf(marker);
  if (at !== -1) {
    const path = trimmed.slice(at + marker.length).split("?")[0];
    return path || null;
  }

  // A bare path, which is what the newer uploads store.
  if (!trimmed.includes("://")) return trimmed.split("?")[0] || null;
  return null;
}
