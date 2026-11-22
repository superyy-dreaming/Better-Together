import jpeg from "npm:jpeg-js@0.4.4";
import { Buffer } from "node:buffer";
import { validateAnalysisImage, sha256 } from "./analysis_image.ts";
import { ServiceError } from "./http.ts";
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
async function rejects(fn: () => unknown | Promise<unknown>, code: string) {
  try {
    await fn();
  } catch (error) {
    assert(
      error instanceof ServiceError && error.code === code,
      `Expected ${code}; received ${error}`,
    );
    return;
  }
  throw new Error(`Expected ${code}`);
}
const pixels = { width: 32, height: 32, data: Buffer.alloc(32 * 32 * 4, 180) };
const jpegBytes = new Uint8Array(jpeg.encode(pixels, 85).data);
Deno.test("analysis JPEG checks actual dimensions and produces data URL, digest and server pHash", async () => {
  const image = await validateAnalysisImage(jpegBytes);
  assert(image.width === 32 && image.height === 32, "Incorrect dimensions");
  assert(
    image.dataUrl ===
      `data:image/jpeg;base64,${Buffer.from(jpegBytes).toString("base64")}`,
    "Image bytes changed",
  );
  assert(
    image.sha256 === await sha256(jpegBytes) &&
      /^[0-9a-f]{16}$/.test(image.phash),
    "Hash not computed",
  );
});
Deno.test("analysis rejects malformed JPEG, PNG, >2 MiB and oversized dimensions before decoding", async () => {
  await rejects(
    () => validateAnalysisImage(new Uint8Array([137, 80, 78, 71])),
    "ANALYSIS_FORMAT",
  );
  await rejects(
    () => validateAnalysisImage(new Uint8Array([255, 216, 255, 217])),
    "ANALYSIS_INVALID",
  );
  await rejects(
    () => validateAnalysisImage(new Uint8Array(2 * 1024 * 1024 + 1)),
    "ANALYSIS_TOO_LARGE",
  );
  const bomb = new Uint8Array([
    255,
    216,
    255,
    192,
    0,
    8,
    8,
    0x7f,
    0xff,
    0,
    1,
    1,
  ]);
  await rejects(() => validateAnalysisImage(bomb), "ANALYSIS_DIMENSIONS");
});
