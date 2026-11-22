import { ServiceError } from "./http.ts";

export type MediaSource = "camera" | "album" | "screenshot";
export type Pixels = { width: number; height: number; data: Uint8Array };

export function localDate(instant: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant);
  const get = (name: string) => parts.find((p) => p.type === name)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

/** EXIF without an offset is interpreted in the team's fixed timezone, never the server timezone. */
export function exifTimestamp(
  value: unknown,
  offset: unknown,
  timezone: string,
): Date | null {
  if (typeof value !== "string") return null;
  const match = value.match(
    /^(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})/,
  );
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  const iso = `${year}-${month}-${day}T${hour}:${minute}:${second}`;
  const zoneOffset =
    typeof offset === "string" && /^[+-]\d{2}:\d{2}$/.test(offset)
      ? offset
      : null;
  if (zoneOffset) {
    const date = new Date(`${iso}${zoneOffset}`);
    return Number.isFinite(date.getTime()) ? date : null;
  }
  const desired = Date.UTC(+year, +month - 1, +day, +hour, +minute, +second);
  let guess = desired;
  for (let i = 0; i < 3; i++) {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date(guess));
    const get = (name: string) =>
      Number(parts.find((p) => p.type === name)?.value ?? 0);
    const actual = Date.UTC(
      get("year"),
      get("month") - 1,
      get("day"),
      get("hour"),
      get("minute"),
      get("second"),
    );
    guess += desired - actual;
  }
  const result = new Date(guess);
  return Number.isFinite(result.getTime()) ? result : null;
}

export function validateCaptureDate(input: {
  source: MediaSource;
  now: Date;
  timezone: string;
  exifDate?: Date | null;
  fileCreatedAt?: string | null;
  screenshotDate?: string | null;
}): { capturedAt: Date; evidence: string } {
  const today = localDate(input.now, input.timezone);
  if (input.source === "camera") {
    return { capturedAt: input.now, evidence: "server_capture_receipt" };
  }
  if (input.source === "screenshot") {
    if (input.screenshotDate !== today) {
      throw new ServiceError(
        "SCREENSHOT_DATE",
        input.screenshotDate
          ? "截图中的日期不是今天，请换一张今天的截图，或现在拍照。"
          : "没有读到截图中的日期，请换一张显示完整日期的截图，或现在拍照。",
      );
    }
    return { capturedAt: input.now, evidence: "screenshot_ocr_date" };
  }
  let date = input.exifDate;
  let evidence = "exif_original";
  if (!date && input.fileCreatedAt) {
    date = new Date(input.fileCreatedAt);
    evidence = "device_file_creation";
  }
  if (!date || !Number.isFinite(date.getTime())) {
    throw new ServiceError(
      "CAPTURE_DATE_MISSING",
      "这张照片没有拍摄日期，请换一张，或现在拍照。",
    );
  }
  if (localDate(date, input.timezone) !== today) {
    throw new ServiceError(
      "CAPTURE_DATE_NOT_TODAY",
      "这张不是今天拍的，请换一张今天的照片，或现在拍照。",
    );
  }
  if (date.getTime() > input.now.getTime() + 5 * 60_000) {
    throw new ServiceError(
      "CAPTURE_DATE_FUTURE",
      "照片时间晚于当前时间，请检查设备时间，或现在拍照。",
    );
  }
  return { capturedAt: date, evidence };
}

/** 64-bit DCT perceptual hash. Hash raw pixels after EXIF orientation normalization. */
export function perceptualHash(image: Pixels): string {
  if (
    image.width < 1 || image.height < 1 ||
    image.data.length < image.width * image.height * 4
  ) throw new ServiceError("IMAGE_INVALID", "照片内容无法读取，请换一张照片。");
  const size = 32;
  const sample = new Float64Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const px = Math.min(
        image.width - 1,
        Math.floor((x + 0.5) * image.width / size),
      );
      const py = Math.min(
        image.height - 1,
        Math.floor((y + 0.5) * image.height / size),
      );
      const index = (py * image.width + px) * 4;
      sample[y * size + x] = 0.299 * image.data[index] +
        0.587 * image.data[index + 1] + 0.114 * image.data[index + 2];
    }
  }
  const coefficients: number[] = [];
  for (let v = 0; v < 8; v++) {
    for (let u = 0; u < 8; u++) {
      let sum = 0;
      for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
          sum += sample[y * size + x] *
            Math.cos((2 * x + 1) * u * Math.PI / 64) *
            Math.cos((2 * y + 1) * v * Math.PI / 64);
        }
      }
      coefficients.push(Math.abs(sum) < 1e-7 ? 0 : sum);
    }
  }
  const sorted = coefficients.slice(1).sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)];
  let bits = 0n;
  for (let i = 0; i < 64; i++) {
    bits = (bits << 1n) | (i > 0 && coefficients[i] > median ? 1n : 0n);
  }
  return bits.toString(16).padStart(16, "0");
}

export function normalizeOrientation(image: Pixels, orientation = 1): Pixels {
  if (orientation <= 1 || orientation > 8) return image;
  const swapped = orientation >= 5;
  const width = swapped ? image.height : image.width;
  const height = swapped ? image.width : image.height;
  const data = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sx = x, sy = y;
      if (orientation === 2) sx = image.width - 1 - x;
      if (orientation === 3) {
        sx = image.width - 1 - x;
        sy = image.height - 1 - y;
      }
      if (orientation === 4) sy = image.height - 1 - y;
      if (orientation === 5) {
        sx = y;
        sy = x;
      }
      if (orientation === 6) {
        sx = y;
        sy = image.height - 1 - x;
      }
      if (orientation === 7) {
        sx = image.width - 1 - y;
        sy = image.height - 1 - x;
      }
      if (orientation === 8) {
        sx = image.width - 1 - y;
        sy = x;
      }
      const source = (sy * image.width + sx) * 4;
      data.set(image.data.subarray(source, source + 4), (y * width + x) * 4);
    }
  }
  return { width, height, data };
}

export function resizeImage(image: Pixels, maxEdge: number): Pixels {
  const scale = Math.min(1, maxEdge / Math.max(image.width, image.height));
  const width = Math.max(1, Math.round(image.width * scale)),
    height = Math.max(1, Math.round(image.height * scale));
  if (scale === 1) return image;
  const data = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const source =
        (Math.min(image.height - 1, Math.floor(y / scale)) * image.width +
          Math.min(image.width - 1, Math.floor(x / scale))) * 4;
      data.set(image.data.subarray(source, source + 4), (y * width + x) * 4);
    }
  }
  return { width, height, data };
}
