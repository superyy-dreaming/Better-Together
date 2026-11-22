// Pinned MIT/BSD/ISC decoders. Original bytes stay private; AI receives a normalized JPEG only.
import exifr from "npm:exifr@7.1.3";
import jpeg from "npm:jpeg-js@0.4.4";
import { PNG } from "npm:pngjs@7.0.0";
import { Buffer } from "node:buffer";
import { ServiceError } from "./http.ts";
import {
  exifTimestamp,
  normalizeOrientation,
  perceptualHash,
  type Pixels,
  resizeImage,
} from "./media_rules.ts";

export async function imageHeader(
  bytes: Uint8Array,
  timezone: string,
): Promise<
  {
    mime: string;
    extension: string;
    capturedAt: Date | null;
    metadata: Record<string, unknown>;
  }
> {
  const isJpeg = bytes[0] === 255 && bytes[1] === 216;
  const isPng = bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 &&
    bytes[3] === 71;
  if (!isJpeg && !isPng) {
    throw new ServiceError(
      "IMAGE_FORMAT",
      "请将照片转换为 JPEG 或 PNG 后上传，原始拍摄日期需保留。",
      415,
    );
  }
  const raw = await exifr.parse(bytes, {
    pick: [
      "DateTimeOriginal",
      "CreateDate",
      "OffsetTimeOriginal",
      "Orientation",
      "ImageWidth",
      "ImageHeight",
      "ExifImageWidth",
      "ExifImageHeight",
    ],
    translateValues: false,
    reviveValues: false,
  }).catch(() => null) as Record<string, unknown> | null;
  return {
    mime: isJpeg ? "image/jpeg" : "image/png",
    extension: isJpeg ? "jpg" : "png",
    capturedAt: exifTimestamp(
      raw?.DateTimeOriginal ?? raw?.CreateDate,
      raw?.OffsetTimeOriginal,
      timezone,
    ),
    metadata: {
      date_original: raw?.DateTimeOriginal ?? null,
      offset_original: raw?.OffsetTimeOriginal ?? null,
      orientation: typeof raw?.Orientation === "number" ? raw.Orientation : 1,
    },
  };
}

export async function inspectImage(
  bytes: Uint8Array,
  timezone: string,
  maxEdge = 1800,
): Promise<
  {
    mime: string;
    extension: string;
    capturedAt: Date | null;
    phash: string;
    jpeg: Uint8Array;
    metadata: Record<string, unknown>;
  }
> {
  let pixels: Pixels;
  let mime: string, extension: string;
  try {
    if (bytes[0] === 0xff && bytes[1] === 0xd8) {
      mime = "image/jpeg";
      extension = "jpg";
      pixels = jpeg.decode(bytes, {
        useTArray: true,
        maxResolutionInMP: 4,
        maxMemoryUsageInMB: 100,
      });
    } else if (
      bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
      bytes[3] === 0x47
    ) {
      mime = "image/png";
      extension = "png";
      const view = new DataView(
        bytes.buffer,
        bytes.byteOffset,
        bytes.byteLength,
      );
      if (
        bytes.byteLength < 24 ||
        view.getUint32(16) * view.getUint32(20) > 4_000_000
      ) {
        throw new ServiceError(
          "IMAGE_TRANSFORM_REQUIRED",
          "照片需要服务端缩图处理，请稍后重试。",
          503,
          true,
        );
      }
      pixels = PNG.sync.read(Buffer.from(bytes));
    } else {
      // HEIC decoding is not reliably portable in the hosted Edge runtime. Never fake a pHash.
      throw new ServiceError(
        "IMAGE_FORMAT",
        "请将照片转换为 JPEG 或 PNG 后上传，原始拍摄日期需保留。",
        415,
      );
    }
  } catch (error) {
    if (error instanceof ServiceError) throw error;
    if (
      error instanceof Error &&
      /maxResolutionInMP|maxMemoryUsageInMB/.test(error.message)
    ) {
      throw new ServiceError(
        "IMAGE_TRANSFORM_REQUIRED",
        "照片需要服务端缩图处理，请稍后重试。",
        503,
        true,
      );
    }
    throw new ServiceError("IMAGE_INVALID", "照片文件无法读取，请换一张照片。");
  }
  const raw = await exifr.parse(bytes, {
    pick: [
      "DateTimeOriginal",
      "CreateDate",
      "OffsetTimeOriginal",
      "Orientation",
    ],
    translateValues: false,
    reviveValues: false,
  }).catch(() => null) as Record<string, unknown> | null;
  const orientation = typeof raw?.Orientation === "number"
    ? raw.Orientation
    : 1;
  // Downsize before orientation to avoid a second full-resolution pixel allocation.
  const analysis = normalizeOrientation(
    resizeImage(pixels, maxEdge),
    orientation,
  );
  const encoded =
    jpeg.encode({ ...analysis, data: Buffer.from(analysis.data) }, 88).data;
  return {
    mime,
    extension,
    capturedAt: exifTimestamp(
      raw?.DateTimeOriginal ?? raw?.CreateDate,
      raw?.OffsetTimeOriginal,
      timezone,
    ),
    phash: perceptualHash(analysis),
    jpeg: new Uint8Array(encoded),
    metadata: {
      width: pixels.width,
      height: pixels.height,
      orientation,
      date_original: raw?.DateTimeOriginal ?? null,
      offset_original: raw?.OffsetTimeOriginal ?? null,
    },
  };
}
