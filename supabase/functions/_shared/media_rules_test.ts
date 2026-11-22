import {
  exifTimestamp,
  localDate,
  normalizeOrientation,
  perceptualHash,
  validateCaptureDate,
} from "./media_rules.ts";
import { retryTime } from "./retry.ts";
import { ServiceError } from "./http.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
function throws(action: () => unknown, code: string) {
  try {
    action();
  } catch (error) {
    if (error instanceof ServiceError && error.code === code) return;
    throw error;
  }
  throw new Error(`Expected ${code}`);
}
const now = new Date("2026-11-18T10:00:00Z");

Deno.test("team timezone determines day across UTC boundary", () => {
  equal(
    localDate(new Date("2026-11-17T18:00:00Z"), "Asia/Shanghai"),
    "2026-11-18",
  );
  equal(
    localDate(new Date("2026-11-18T01:00:00Z"), "America/Los_Angeles"),
    "2026-11-17",
  );
});
Deno.test("EXIF clock without zone is interpreted in fixed team timezone", () => {
  equal(
    exifTimestamp("2026:11:18 09:00:00", null, "Asia/Shanghai")?.toISOString(),
    "2026-11-18T01:00:00.000Z",
  );
  equal(
    exifTimestamp("2026:07:18 09:00:00", null, "America/New_York")
      ?.toISOString(),
    "2026-07-18T13:00:00.000Z",
  );
  equal(
    exifTimestamp("2026:11:18 09:00:00", "+09:00", "Asia/Shanghai")
      ?.toISOString(),
    "2026-11-18T00:00:00.000Z",
  );
});
Deno.test("old, absent and future capture evidence is rejected individually", () => {
  throws(
    () =>
      validateCaptureDate({
        source: "album",
        now,
        timezone: "Asia/Shanghai",
        exifDate: new Date("2026-11-16T22:00:00Z"),
      }),
    "CAPTURE_DATE_NOT_TODAY",
  );
  throws(
    () =>
      validateCaptureDate({ source: "album", now, timezone: "Asia/Shanghai" }),
    "CAPTURE_DATE_MISSING",
  );
  throws(
    () =>
      validateCaptureDate({
        source: "album",
        now,
        timezone: "Asia/Shanghai",
        exifDate: new Date("2026-11-18T12:00:00Z"),
      }),
    "CAPTURE_DATE_FUTURE",
  );
});
Deno.test("EXIF is authoritative over client file creation fallback", () => {
  throws(
    () =>
      validateCaptureDate({
        source: "album",
        now,
        timezone: "Asia/Shanghai",
        exifDate: new Date("2026-11-16T22:00:00Z"),
        fileCreatedAt: now.toISOString(),
      }),
    "CAPTURE_DATE_NOT_TODAY",
  );
  equal(
    validateCaptureDate({
      source: "album",
      now,
      timezone: "Asia/Shanghai",
      fileCreatedAt: now.toISOString(),
    }).evidence,
    "device_file_creation",
  );
});
Deno.test("screenshot must have matching visible date; camera time is server time", () => {
  throws(
    () =>
      validateCaptureDate({
        source: "screenshot",
        now,
        timezone: "Asia/Shanghai",
        screenshotDate: "2026-11-17",
      }),
    "SCREENSHOT_DATE",
  );
  equal(
    validateCaptureDate({
      source: "camera",
      now,
      timezone: "Asia/Shanghai",
      fileCreatedAt: "2020-01-01",
    }).capturedAt,
    now,
  );
});
Deno.test("pixel hash stable across exact integer scaling, differs for distinct content", () => {
  const small = { width: 32, height: 32, data: new Uint8Array(32 * 32 * 4) };
  const large = { width: 64, height: 64, data: new Uint8Array(64 * 64 * 4) };
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      const value = (Math.floor(x / 2) * 17 + Math.floor(y / 2) * 31) % 255;
      large.data.set([value, value, value, 255], (y * 64 + x) * 4);
      small.data.set(
        [value, value, value, 255],
        (Math.floor(y / 2) * 32 + Math.floor(x / 2)) * 4,
      );
    }
  }
  equal(perceptualHash(small), perceptualHash(large));
  const blank = { ...small, data: new Uint8Array(small.data.length) };
  if (perceptualHash(small) === perceptualHash(blank)) {
    throw new Error("Different images collided");
  }
});
Deno.test("EXIF orientation 6 rotates pixels clockwise", () => {
  const image = {
    width: 2,
    height: 1,
    data: new Uint8Array([1, 2, 3, 255, 4, 5, 6, 255]),
  };
  const rotated = normalizeOrientation(image, 6);
  equal([rotated.width, rotated.height], [1, 2]);
  equal([...rotated.data], [1, 2, 3, 255, 4, 5, 6, 255]);
});
Deno.test("retry respects dependency errors, maximum attempts and local-day boundary", () => {
  equal(
    retryTime(
      new ServiceError("AI_UNAVAILABLE", "", 503, true),
      1,
      now.toISOString(),
      "Asia/Shanghai",
      now,
    ),
    "2026-11-18T10:00:30.000Z",
  );
  equal(
    retryTime(
      new ServiceError("AI_REFUSAL", "", 422, false),
      1,
      now.toISOString(),
      "Asia/Shanghai",
      now,
    ),
    null,
  );
  equal(
    retryTime(new Error("network"), 8, now.toISOString(), "Asia/Shanghai", now),
    null,
  );
  equal(
    retryTime(
      new Error("network"),
      1,
      now.toISOString(),
      "Asia/Shanghai",
      new Date("2026-11-18T15:59:45Z"),
    ),
    null,
  );
});
