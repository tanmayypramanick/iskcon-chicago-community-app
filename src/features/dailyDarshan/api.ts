import { compressImage } from "../../lib/compressImage";
import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
// The picture goes to the same message-images bucket as a chat photo, and the
// migration only accepts a URL from it, so the uploader is the messaging one
// rather than a second bucket and a second policy to keep in step.
import { uploadMessageImage } from "../messaging/api";
import { isConnectionProblem } from "../services/format";
import type {
  DailyDarshan,
  DarshanDeity,
  DarshanImage,
  PickedMessageImage,
  PublishDailyDarshanInput,
} from "./types";
import { FALLBACK_DARSHAN_DEITIES, MAX_DARSHAN_IMAGES } from "./types";

export { uploadMessageImage };

/**
 * Darshan arrives with its own migration, which a temple's database may not
 * have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * A read treats that as "no darshan posted yet" rather than as a failure: a red
 * error where a quiet empty state belongs reads as the app being broken.
 */
function isMigrationPending(error: { code?: string } | null) {
  return ["PGRST202", "42883", "42P01", "PGRST205"].includes(error?.code ?? "");
}

/**
 * The server hands each day's pictures back as jsonb. Anything that is not an
 * array of objects with a URL is dropped here rather than reaching a screen
 * that would render an empty frame — a day with one unreadable row is still a
 * day of darshan.
 */
function normalizeImages(value: unknown): DarshanImage[] {
  if (!Array.isArray(value)) return [];
  const text = (candidate: unknown) =>
    typeof candidate === "string" && candidate.trim() ? candidate.trim() : null;

  return value
    .map((entry, index) => {
      const row = entry as Record<string, unknown> | null;
      const imageUrl = text(row?.imageUrl) ?? text(row?.image_url);
      if (!imageUrl) return null;
      return {
        imageUrl,
        deity: text(row?.deity),
        dressedBy: text(row?.dressedBy) ?? text(row?.dressed_by),
        position:
          typeof row?.position === "number" ? row.position : index,
      } satisfies DarshanImage;
    })
    .filter((image): image is DarshanImage => image !== null)
    .sort((left, right) => left.position - right.position);
}

function normalizeDarshan(row: Record<string, unknown>): DailyDarshan {
  return {
    ...(row as unknown as DailyDarshan),
    images: normalizeImages(row.images),
  };
}

/** Newest first, the days the temple has posted. */
export async function fetchDailyDarshan(
  limit = 30,
): Promise<DailyDarshan[]> {
  const { data, error } = await getSupabaseClient().rpc("list_daily_darshan", {
    p_limit: limit,
  });
  // A transport failure means the server is unreachable; a Postgres error
  // means it answered, so the connection is fine.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return [];
    throw error;
  }
  return ((data ?? []) as Record<string, unknown>[]).map(normalizeDarshan);
}

/**
 * The one day the Home card previews. The function returns a single row, but
 * PostgREST hands back a set-returning function as an array, so both shapes are
 * accepted rather than trusting one and rendering nothing on the other.
 */
export async function fetchLatestDailyDarshan(): Promise<DailyDarshan | null> {
  const { data, error } = await getSupabaseClient().rpc(
    "latest_daily_darshan",
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return null;
    throw error;
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") return null;
  return normalizeDarshan(row as Record<string, unknown>);
}

/**
 * The Deities the temple can choose between.
 *
 * The temple asked to "choose from the list which Deities" rather than type
 * Them, so this is a read of migration 0080's `temple_deities` catalogue. The
 * default arguments are exactly what a picker wants — the retired Deities are
 * left out of it, while a picture posted before one was retired keeps showing
 * Their name, because the darshan stores the name and not a reference.
 *
 * It is tolerant twice over: a database without 0080 answers with one of the
 * missing-object codes, and a catalogue that exists but is empty answers with
 * nothing. Both give back the three the temple named, because a picker with
 * nothing in it stops a day being posted at all.
 */
export async function fetchDarshanDeities(): Promise<DarshanDeity[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_temple_deities",
    {},
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return fallbackDeities();
    throw error;
  }
  const named = normalizeDeities(data);
  return named.length ? named : fallbackDeities();
}

function fallbackDeities(): DarshanDeity[] {
  return FALLBACK_DARSHAN_DEITIES.map((name) => ({ id: null, name }));
}

/**
 * The catalogue is read for its names, in the order the server gave them —
 * `display_order` is the temple's altar order and re-sorting it here would
 * throw that away. Duplicates are dropped: two rows with the same name would
 * draw the same chip twice.
 */
function normalizeDeities(value: unknown): DarshanDeity[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const deities: DarshanDeity[] = [];

  for (const entry of value) {
    const row = entry as Record<string, unknown> | null;
    const name = typeof row?.name === "string" ? row.name.trim() : "";
    if (!name || seen.has(name)) continue;
    seen.add(name);
    deities.push({
      id: typeof row?.id === "string" ? row.id : null,
      name,
    });
  }
  return deities;
}

/**
 * The writes deliberately do not tolerate a missing migration. There is
 * nothing to post or take down until it has run, so an error here is a real one
 * and whoever tapped should be told rather than watching nothing happen.
 */
async function runRpc(
  name: string,
  params: Record<string, unknown>,
): Promise<unknown> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data;
}

/**
 * Posts one day. The images are already in storage by the time this is called —
 * `publish_daily_darshan` records URLs, so a half-finished upload must never
 * become a darshan pointing at nothing.
 */
export async function publishDailyDarshan(
  input: PublishDailyDarshanInput,
): Promise<string> {
  if (input.images.length < 1) {
    throw new Error("Add at least one photograph.");
  }
  // The server enforces this too; refusing here keeps the round trip off a
  // temple wifi connection that has just carried five photographs.
  if (input.images.length > MAX_DARSHAN_IMAGES) {
    throw new Error(`Up to ${MAX_DARSHAN_IMAGES} photographs can be posted.`);
  }

  const data = await runRpc("publish_daily_darshan", {
    p_darshan_on: input.darshanOn,
    p_note: input.note,
    // Positions are assigned here rather than trusted from the caller, so the
    // order the temple arranged is the order every devotee reads.
    p_images: input.images.map((image, index) => ({
      imageUrl: image.imageUrl,
      deity: image.deity,
      dressedBy: image.dressedBy,
      position: index,
    })),
  });
  return data as string;
}

/** The day goes for good. The server decides who may; `can_delete` says so. */
export async function deleteDailyDarshan(id: string): Promise<unknown> {
  return runRpc("delete_daily_darshan", { p_id: id });
}

/**
 * expo-image-picker is a native module, loaded late so a binary built before
 * the dependency existed still starts.
 *
 * `await import()` is not enough: Metro compiles it to a synchronous require
 * and the missing-native-module error is raised while the module body
 * evaluates, escaping the promise and reaching the devotee as a red screen. A
 * plain require inside try/catch does catch it.
 */
const REBUILD_MESSAGE =
  "This copy of the app was built before pictures were added. Rebuild it (npm run ios / npm run android) and try again.";

type ImagePickerModule = typeof import("expo-image-picker");

function loadImagePicker(): ImagePickerModule {
  let candidate: unknown;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    candidate = require("expo-image-picker");
  } catch {
    throw new Error(REBUILD_MESSAGE);
  }

  // Metro's interop sometimes nests the real module under `default`.
  const picker = (candidate as { default?: unknown })?.default ?? candidate;
  const api = picker as Partial<ImagePickerModule> | undefined;
  if (
    !api ||
    typeof api.launchImageLibraryAsync !== "function" ||
    typeof api.launchCameraAsync !== "function" ||
    typeof api.requestCameraPermissionsAsync !== "function" ||
    typeof api.requestMediaLibraryPermissionsAsync !== "function"
  ) {
    throw new Error(REBUILD_MESSAGE);
  }
  return api as ImagePickerModule;
}

function extensionFor(mimeType: string) {
  if (mimeType.includes("png")) return "png";
  if (mimeType.includes("webp")) return "webp";
  return "jpg";
}

/**
 * A darshan photograph is looked at full screen and is the whole point of the
 * feature, so it is kept larger than a chat picture — but still far below what
 * a phone camera produces, because five of those is a lot of bytes on temple
 * wifi and nobody can see the difference on a phone.
 */
const DARSHAN_IMAGE_LIMITS = { maxWidth: 1600, quality: 0.72 } as const;

/**
 * Up to `remaining` pictures in one go. The library allows a multiple
 * selection because choosing five one at a time is five trips through a
 * permission-gated sheet; the camera is inherently one at a time.
 *
 * No crop step: the Deities are framed by whoever took the photograph, and
 * forcing a square would cut Them out of it. Returns [] when they cancel.
 */
export async function pickDarshanImages(
  source: "library" | "camera",
  remaining: number,
): Promise<PickedMessageImage[]> {
  if (remaining < 1) return [];
  const ImagePicker = loadImagePicker();
  const permission =
    source === "camera"
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error(
      source === "camera"
        ? "Allow camera access to take a darshan photo."
        : "Allow photo access to choose darshan pictures.",
    );
  }

  const options: import("expo-image-picker").ImagePickerOptions = {
    mediaTypes: ["images"],
    quality: 0.8,
    allowsMultipleSelection: source === "library",
    selectionLimit: source === "library" ? remaining : 1,
  };
  const result =
    source === "camera"
      ? await ImagePicker.launchCameraAsync(options)
      : await ImagePicker.launchImageLibraryAsync(options);

  if (result.canceled) return [];

  // A picker that ignores selectionLimit — some Android gallery apps do — must
  // not be allowed to push the composer past the cap.
  const assets = result.assets.slice(0, remaining);
  return Promise.all(
    assets.map(async (asset) => {
      const shrunk = await compressImage(
        asset.uri,
        asset.mimeType ?? "image/jpeg",
        DARSHAN_IMAGE_LIMITS,
      );
      return {
        uri: shrunk.uri,
        mimeType: shrunk.mimeType,
        fileName: asset.fileName ?? `darshan.${extensionFor(shrunk.mimeType)}`,
      };
    }),
  );
}
