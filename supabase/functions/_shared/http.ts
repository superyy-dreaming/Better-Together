export class ServiceError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 400,
    public retryable = false,
  ) {
    super(message);
  }
}

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, x-job-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof ServiceError) {
    return json(
      { error: { code: error.code, message: error.message } },
      error.status,
    );
  }
  console.error(
    JSON.stringify({
      event: "unexpected_error",
      message: error instanceof Error ? error.message : String(error),
    }),
  );
  return json({
    error: {
      code: "SERVICE_UNAVAILABLE",
      message: "暂时无法完成这次操作，请稍后重试。",
    },
  }, 503);
}

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new ServiceError(
      "CONFIGURATION_REQUIRED",
      "服务尚未配置完成，请联系内测管理员。",
      503,
    );
  }
  return value;
}

export function requirePost(request: Request): Response | null {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") {
    return json({
      error: { code: "METHOD_NOT_ALLOWED", message: "请使用 POST 请求。" },
    }, 405);
  }
  return null;
}

export async function checkJobSecret(request: Request): Promise<void> {
  const expected = requiredEnv("JOB_SECRET");
  const supplied = request.headers.get("x-job-secret") ?? "";
  const encoder = new TextEncoder();
  const hashes = await Promise.all(
    [expected, supplied].map((v) =>
      crypto.subtle.digest("SHA-256", encoder.encode(v))
    ),
  );
  const [a, b] = hashes.map((v) => new Uint8Array(v));
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  if (difference !== 0) {
    throw new ServiceError("UNAUTHORIZED", "需要有效的任务凭据。", 401);
  }
}

export function validUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

export async function boundedBody(
  request: Request,
  maximum: number,
): Promise<Uint8Array<ArrayBuffer>> {
  if (Number(request.headers.get("content-length") ?? 0) > maximum) {
    throw new ServiceError(
      "REQUEST_TOO_LARGE",
      "提交内容过大，请缩小照片或文字后重试。",
      413,
    );
  }
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximum) {
        await reader.cancel();
        throw new ServiceError(
          "REQUEST_TOO_LARGE",
          "提交内容过大，请缩小照片或文字后重试。",
          413,
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}
