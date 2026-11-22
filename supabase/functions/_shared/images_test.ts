import jpeg from "npm:jpeg-js@0.4.4";
import { PNG } from "npm:pngjs@7.0.0";
import { Buffer } from "node:buffer";
import { imageHeader, inspectImage } from "./images.ts";
import { ServiceError } from "./http.ts";

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
const pixels = { width: 32, height: 32, data: Buffer.alloc(32 * 32 * 4) };
for (let i = 0; i < 1024; i++) {
  pixels.data[i * 4] = i % 32 * 8;
  pixels.data[i * 4 + 1] = Math.floor(i / 32) * 8;
  pixels.data[i * 4 + 2] = 100;
  pixels.data[i * 4 + 3] = 255;
}

Deno.test("server decodes real PNG/JPEG bytes and computes normalized analysis JPEG", async () => {
  for (
    const [bytes, mime] of [[PNG.sync.write(pixels), "image/png"], [
      jpeg.encode(pixels, 92).data,
      "image/jpeg",
    ]] as const
  ) {
    const result = await inspectImage(bytes, "Asia/Shanghai");
    assert(result.mime === mime, "Incorrect media type");
    assert(/^[0-9a-f]{16}$/.test(result.phash), "Hash was not computed");
    assert(
      result.jpeg[0] === 255 && result.jpeg[1] === 216,
      "Analysis is not JPEG",
    );
    assert(result.capturedAt === null, "Decoder invented a date");
    assert(
      result.metadata.width === 32 && result.metadata.height === 32,
      "Size incorrect",
    );
  }
});
Deno.test("malformed pixels and unsupported format produce actionable errors", async () => {
  for (
    const [bytes, code] of [
      [new Uint8Array([255, 216, 0, 0]), "IMAGE_INVALID"],
      [new Uint8Array([0, 0, 0, 20]), "IMAGE_FORMAT"],
    ] as const
  ) {
    try {
      await inspectImage(bytes, "UTC");
      throw new Error("Accepted corrupt image");
    } catch (error) {
      assert(
        error instanceof ServiceError && error.code === code,
        "Unexpected error type",
      );
    }
  }
});
Deno.test("PNG advertised dimensions reject decompression bomb before decode", async () => {
  const bytes = new Uint8Array(24);
  bytes.set([137, 80, 78, 71]);
  const view = new DataView(bytes.buffer);
  view.setUint32(16, 20000);
  view.setUint32(20, 20000);
  try {
    await inspectImage(bytes, "UTC");
    throw new Error("Accepted oversized image");
  } catch (error) {
    assert(
      error instanceof ServiceError &&
        error.code === "IMAGE_TRANSFORM_REQUIRED",
      "Unexpected error",
    );
  }
});
Deno.test("original EXIF capture date survives separate server image transformation", async () => {
  const tiff = new Uint8Array(95);
  const view = new DataView(tiff.buffer);
  tiff.set([73, 73, 42, 0, 8, 0, 0, 0]);
  view.setUint16(8, 2, true);
  function entry(
    at: number,
    tag: number,
    type: number,
    count: number,
    value: number,
  ) {
    view.setUint16(at, tag, true);
    view.setUint16(at + 2, type, true);
    view.setUint32(at + 4, count, true);
    view.setUint32(at + 8, value, true);
  }
  entry(10, 274, 3, 1, 6);
  entry(22, 34665, 4, 1, 38);
  view.setUint16(38, 2, true);
  entry(40, 36867, 2, 20, 68);
  entry(52, 36881, 2, 7, 88);
  tiff.set(new TextEncoder().encode("2026:11:18 09:10:11\0"), 68);
  tiff.set(new TextEncoder().encode("+08:00\0"), 88);
  const original = jpeg.encode(pixels, 92).data;
  const app1 = new Uint8Array(4 + 6 + tiff.length);
  app1.set([255, 225, 0, 103, 69, 120, 105, 102, 0, 0]);
  app1.set(tiff, 10);
  const bytes = new Uint8Array(original.length + app1.length);
  bytes.set(original.subarray(0, 2));
  bytes.set(app1, 2);
  bytes.set(original.subarray(2), 2 + app1.length);
  const header = await imageHeader(bytes, "America/New_York");
  assert(
    header.capturedAt?.toISOString() === "2026-11-18T01:10:11.000Z",
    "EXIF date or offset lost",
  );
  assert(header.metadata.orientation === 6, "Original orientation lost");
});
