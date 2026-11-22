import {
  cleanupPaths,
  type CleanupPayload,
  cleanupRetryTime,
  removeEvidence,
} from "./cleanup.ts";
import { ServiceError } from "./http.ts";
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
const media = {
  id: "media-id",
  path: "user/batch/image.jpg",
  analysis_path: "user/batch/image.analysis.jpg",
  deleted_at: "2026-11-18T00:00:00Z",
};
const payload: CleanupPayload = {
  media_id: "media-id",
  bucket: "evidence",
  paths: [media.path, media.analysis_path],
};
Deno.test("cleanup authorizes exact original and analysis paths of a deleted media row", () => {
  assert(
    cleanupPaths(payload, media).length === 2,
    "Analysis must be removed too",
  );
  for (
    const input of [{ ...payload, paths: [media.path] }, {
      ...payload,
      paths: [media.path, "other/private.jpg"],
    }, { ...payload, media_id: "other" }]
  ) {
    try {
      cleanupPaths(input, media);
      throw new Error("Accepted foreign/incomplete paths");
    } catch (error) {
      assert(error instanceof ServiceError, "Expected ownership check");
    }
  }
  try {
    cleanupPaths(payload, { ...media, deleted_at: null });
    throw new Error("Deleted active photo");
  } catch (error) {
    assert(error instanceof ServiceError, "Expected deletion guard");
  }
});
Deno.test("transient cleanup failure retries after arbitrary age and removes both objects on recovery", async () => {
  const paths = cleanupPaths(payload, media);
  let attempts = 0;
  const remove = (received: string[]) => {
    assert(received.length === 2, "Incomplete removal");
    attempts++;
    return Promise.resolve({
      error: attempts === 1 ? { name: "StorageUnavailable" } : null,
    });
  };
  try {
    await removeEvidence(paths, remove);
    throw new Error("Ignored remove error");
  } catch (error) {
    assert(
      error instanceof ServiceError && error.retryable,
      "Storage failure must retry",
    );
  }
  assert(
    cleanupRetryTime(100, new Date("2027-01-01T00:00:00Z")) ===
      "2027-01-01T06:00:00.000Z",
    "Cleanup expired or retry unbounded",
  );
  await removeEvidence(paths, remove);
  assert(attempts === 2, "No recovery attempt");
});
