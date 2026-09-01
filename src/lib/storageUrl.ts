import { useEffect, useState } from "react";

/**
 * Turning a stored image reference into a URL that will actually load.
 *
 * The three Storage buckets — devotee-photos, message-images and
 * newsletter-files — were created `public = true`, which means Supabase serves
 * every object at /storage/v1/object/public/... to anybody at all, signed in
 * or not, forever. Devotees' faces, photographs sent inside private direct
 * messages, and the temple's newsletters were all outside the sign-in wall
 * that the privacy screen promises devotees is there. The `for select to
 * authenticated` policies two of those buckets carry were dead code: a public
 * bucket bypasses row level security on reads entirely.
 *
 * The buckets are now private (202608310088). Objects are reachable only
 * through a signed URL, which is minted for one object, for one hour.
 *
 * WHAT IS STORED HAS NOT CHANGED, deliberately. users.photo_url,
 * messages.image_url, daily_darshan_images.image_url and the newsletter rows
 * still hold the public-URL-shaped string that `getPublicUrl` builds. That
 * string is no longer fetchable, but it still names the bucket and the object
 * path, which is all anybody needs — so there is no data migration, and the
 * server-side checks that validate the shape of a darshan photo URL keep
 * working unchanged. Treat a stored value as a REFERENCE, not as a URL.
 *
 * The consequence, and the thing to remember when adding a screen: rendering a
 * stored value directly now shows a broken image. Every remote image goes
 * through `useSignedUrl`.
 */

const PUBLIC_MARKER = "/storage/v1/object/public/";

/** How long a minted URL is asked to last. */
const SIGNED_URL_TTL_SECONDS = 60 * 60;

/**
 * Re-signed a little before it truly expires, so a devotee looking at a long
 * list is never handed a URL that dies mid-scroll.
 */
const CACHE_TTL_MS = (SIGNED_URL_TTL_SECONDS - 5 * 60) * 1000;

export type StorageRef = { bucket: string; path: string };

/**
 * Splits a stored reference into its bucket and object path.
 *
 * Accepts the public-URL form every existing row holds, and a plain
 * `bucket/path` form, so a future change of what gets written needs no
 * migration either. Anything else — a data: URI, a local file:// from an
 * image picker, an absolute URL somewhere else entirely — returns null and is
 * rendered as-is, which is what those need.
 */
export function parseStorageRef(value: string | null | undefined): StorageRef | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  const marker = trimmed.indexOf(PUBLIC_MARKER);
  if (marker !== -1) {
    const rest = trimmed.slice(marker + PUBLIC_MARKER.length);
    const slash = rest.indexOf("/");
    if (slash <= 0) return null;
    const bucket = rest.slice(0, slash);
    // A stored URL can carry a query string; the object path never does.
    const path = rest.slice(slash + 1).split(/[?#]/)[0];
    if (!bucket || !path) return null;
    return { bucket, path: decodeURIComponent(path) };
  }

  // Not a URL of any kind, and shaped like `bucket/path`.
  if (/^[a-z0-9][a-z0-9.-]*\//.test(trimmed) && !trimmed.includes("://")) {
    const slash = trimmed.indexOf("/");
    return { bucket: trimmed.slice(0, slash), path: trimmed.slice(slash + 1) };
  }

  return null;
}

type CacheEntry = { url: string; expiresAt: number };

const cache = new Map<string, CacheEntry>();
/** One in-flight request per object, so a list of fifty avatars asks once each. */
const inFlight = new Map<string, Promise<string | null>>();

const keyOf = (ref: StorageRef) => `${ref.bucket}/${ref.path}`;

/**
 * Requests waiting to be signed, grouped so one round trip covers a whole
 * screen. createSignedUrls takes many paths at once; asking per image turned a
 * devotee list into one request per face.
 */
const pending = new Map<string, { paths: Set<string>; timer: ReturnType<typeof setTimeout> }>();
const waiters = new Map<string, ((url: string | null) => void)[]>();

async function flush(bucket: string) {
  const batch = pending.get(bucket);
  if (!batch) return;
  pending.delete(bucket);
  const paths = [...batch.paths];

  const settle = (path: string, url: string | null) => {
    const key = `${bucket}/${path}`;
    if (url) cache.set(key, { url, expiresAt: Date.now() + CACHE_TTL_MS });
    for (const resolve of waiters.get(key) ?? []) resolve(url);
    waiters.delete(key);
    inFlight.delete(key);
  };

  try {
    // A lazy require rather than a dynamic import, matching documentPicker.ts:
    // Metro rewrites `await import()` into a module-scope require anyway, and
    // a real require works under the test runner too, where a dynamic import
    // throws ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING_FLAG. Keeping it out of
    // module scope still matters — building the client touches native storage
    // that a screen test does not have.
    const { getSupabaseClient } = require("./supabase") as typeof import("./supabase");
    const { data, error } = await getSupabaseClient()
      .storage.from(bucket)
      .createSignedUrls(paths, SIGNED_URL_TTL_SECONDS);

    if (error || !data) {
      for (const path of paths) settle(path, null);
      return;
    }
    const byPath = new Map(
      data.map((row) => [row.path ?? "", row.signedUrl ?? null]),
    );
    for (const path of paths) settle(path, byPath.get(path) ?? null);
  } catch {
    // Offline, or the client could not be built. Null renders the placeholder
    // rather than a broken image, and the next mount tries again.
    for (const path of paths) settle(path, null);
  }
}

function signedUrlFor(ref: StorageRef): Promise<string | null> {
  const key = keyOf(ref);

  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) {
    return Promise.resolve(cached.url);
  }

  const existing = inFlight.get(key);
  if (existing) return existing;

  const promise = new Promise<string | null>((resolve) => {
    const list = waiters.get(key) ?? [];
    list.push(resolve);
    waiters.set(key, list);

    const batch = pending.get(ref.bucket);
    if (batch) {
      batch.paths.add(ref.path);
      return;
    }
    pending.set(ref.bucket, {
      paths: new Set([ref.path]),
      // One tick is enough to collect a screen's worth without delaying paint.
      timer: setTimeout(() => void flush(ref.bucket), 16),
    });
  });

  inFlight.set(key, promise);
  return promise;
}

/**
 * The signed URL for a stored image reference, or the value unchanged when it
 * is not a Storage reference at all (a locally picked file, say).
 *
 * Returns null while the first signature is in flight, so a caller can show
 * its placeholder rather than a flash of broken image.
 */
export function useSignedUrl(value: string | null | undefined): string | null {
  const ref = parseStorageRef(value);
  const key = ref ? keyOf(ref) : null;

  const [url, setUrl] = useState<string | null>(() => {
    if (!ref) return value ?? null;
    const cached = cache.get(keyOf(ref));
    return cached && cached.expiresAt > Date.now() ? cached.url : null;
  });

  useEffect(() => {
    if (!ref) {
      setUrl(value ?? null);
      return;
    }
    let active = true;
    const cached = cache.get(keyOf(ref));
    if (cached && cached.expiresAt > Date.now()) {
      setUrl(cached.url);
      return;
    }
    void signedUrlFor(ref).then((next) => {
      if (active) setUrl(next);
    });
    return () => {
      active = false;
    };
    // `key` is the identity of the object; `ref` is a fresh object each render.
  }, [key, value]);

  return url;
}

/**
 * The one-shot form, for code that is not a component — sharing a newsletter
 * file, for instance, where the URL is downloaded rather than rendered.
 */
export async function getSignedUrl(
  value: string | null | undefined,
): Promise<string | null> {
  const ref = parseStorageRef(value);
  if (!ref) return value ?? null;
  return signedUrlFor(ref);
}

/** Testing seam: forgets every minted URL. */
export function clearSignedUrlCache() {
  cache.clear();
  inFlight.clear();
  waiters.clear();
  for (const batch of pending.values()) clearTimeout(batch.timer);
  pending.clear();
}
