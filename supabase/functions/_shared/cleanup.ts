import { ServiceError } from "./http.ts";

export type CleanupPayload = {
  media_id: string;
  bucket: "evidence";
  paths: string[];
};
export type CleanupMedia = {
  id: string;
  path: string;
  analysis_path: string | null;
  thumbnail_path?: string | null;
  user_id?: string; batch_id?: string;
  deleted_at: string | null;
};
export function cleanupPaths(
  payload: CleanupPayload,
  media: CleanupMedia,
): string[] {
  if (
    payload.media_id !== media.id || payload.bucket !== "evidence" ||
    !media.deleted_at
  ) {
    throw new ServiceError(
      "CLEANUP_TARGET_INVALID",
      "Cleanup target is not marked for deletion",
      409,
      false,
    );
  }
  const actual = [
    media.path,
    ...media.analysis_path ? [media.analysis_path] : [],
  ].sort();
  if (
    !Array.isArray(payload.paths) ||
    JSON.stringify([...new Set(payload.paths)].sort()) !==
      JSON.stringify(actual)
  ) {
    throw new ServiceError(
      "CLEANUP_PATH_MISMATCH",
      "Cleanup paths do not match deleted media",
      409,
      false,
    );
  }
  return [
    ...new Set([
      ...actual,
      ...(media.thumbnail_path ? [media.thumbnail_path] : media.user_id && media.batch_id ? [`${media.user_id}/${media.batch_id}/${media.id}.thumb.jpg`] : []),
    ]),
  ];
}
/** Deletion remains pending until dependency recovery; unlike AI it has no expiry. */
export function cleanupRetryTime(attempt: number, now = new Date()): string {
  return new Date(
    now.getTime() +
      Math.min(
        6 * 3600_000,
        60_000 * 2 ** Math.min(16, Math.max(0, attempt - 1)),
      ),
  ).toISOString();
}

export async function removeEvidence(
  paths: string[],
  remove: (paths: string[]) => PromiseLike<{ error: { name: string } | null }>,
): Promise<void> {
  const { error } = await remove(paths);
  if (error) {
    throw new ServiceError(
      "STORAGE_CLEANUP_UNAVAILABLE",
      "Private originals are awaiting deletion",
      503,
      true,
    );
  }
}
