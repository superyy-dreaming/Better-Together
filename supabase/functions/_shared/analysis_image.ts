import { Buffer } from "node:buffer";
import jpeg from "npm:jpeg-js@0.4.4";
import { ServiceError } from "./http.ts";
import { perceptualHash } from "./media_rules.ts";
const maximumBytes = 2 * 1024 * 1024;
export type AnalysisImage = {
  bytes: Uint8Array;
  dataUrl: string;
  sha256: string;
  phash: string;
  width: number;
  height: number;
};
export async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes)),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function jpegDimensions(bytes: Uint8Array): { width: number; height: number } {
  // Parse dimensions before decode, so even narrow/oversized images cannot
  // allocate their advertised pixel buffers inside the hosted Edge process.
  if (bytes[0] !== 255 || bytes[1] !== 216) {
    throw new ServiceError("ANALYSIS_FORMAT", "识别图片必须是 JPEG。", 415);
  }
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 255) break;
    while (bytes[offset] === 255) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) break;
    if ([0xc0, 0xc1, 0xc2].includes(marker)) {
      if (length < 8) break;
      return {
        height: (bytes[offset + 3] << 8) | bytes[offset + 4],
        width: (bytes[offset + 5] << 8) | bytes[offset + 6],
      };
    }
    offset += length;
  }
  throw new ServiceError(
    "ANALYSIS_INVALID",
    "识别图片无法读取，请重新选择照片。",
  );
}

export async function validateAnalysisImage(
  bytes: Uint8Array,
): Promise<AnalysisImage> {
  if (!bytes.length || bytes.length > maximumBytes) {
    throw new ServiceError(
      "ANALYSIS_TOO_LARGE",
      "识别图片最多 2 MB，请重新压缩。",
      413,
    );
  }
  const { width, height } = jpegDimensions(bytes);
  if (width < 1 || height < 1 || width > 1600 || height > 1600) {
    throw new ServiceError(
      "ANALYSIS_DIMENSIONS",
      "识别图片长边最多 1600 像素。",
      413,
    );
  }
  try {
    const pixels = jpeg.decode(bytes, {
      useTArray: true,
      maxResolutionInMP: 2.56,
      maxMemoryUsageInMB: 64,
      tolerantDecoding: false,
    });
    if (pixels.width !== width || pixels.height !== height) {
      throw new Error("dimension mismatch");
    }
    return {
      bytes,
      dataUrl: `data:image/jpeg;base64,${
        Buffer.from(bytes).toString("base64")
      }`,
      sha256: await sha256(bytes),
      phash: perceptualHash(pixels),
      width,
      height,
    };
  } catch {
    throw new ServiceError(
      "ANALYSIS_INVALID",
      "识别图片无法读取，请重新选择照片。",
    );
  }
}

