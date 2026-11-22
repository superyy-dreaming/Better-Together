import { requiredEnv, ServiceError } from "./http.ts";

export type PushPayload = {
  title: string;
  body: string;
  kind: string;
  target_id?: string;
  notification_id?: string;
};
const encoder = new TextEncoder();
function base64url(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replaceAll("=", "");
}
function encode(value: object): string {
  return base64url(encoder.encode(JSON.stringify(value)));
}
let cachedApns: { token: string; expires: number } | null = null;

export async function apnsToken(now = Date.now()): Promise<string> {
  if (cachedApns && cachedApns.expires > now) return cachedApns.token;
  const pem = requiredEnv("APNS_PRIVATE_KEY").replaceAll("\\n", "\n");
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(body), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const unsigned = `${
    encode({ alg: "ES256", kid: requiredEnv("APNS_KEY_ID") })
  }.${
    encode({ iss: requiredEnv("APNS_TEAM_ID"), iat: Math.floor(now / 1000) })
  }`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(unsigned),
  );
  const token = `${unsigned}.${base64url(new Uint8Array(signature))}`;
  cachedApns = { token, expires: now + 45 * 60_000 };
  return token;
}

export async function sendApns(
  token: string,
  payload: PushPayload,
  fetcher = fetch,
): Promise<void> {
  const endpoint = Deno.env.get("APNS_ENVIRONMENT") === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const result = await fetcher(
    `${endpoint}/3/device/${encodeURIComponent(token)}`,
    {
      method: "POST",
      signal: AbortSignal.timeout(15_000),
      headers: {
        authorization: `bearer ${await apnsToken()}`,
        "apns-topic": requiredEnv("APNS_BUNDLE_ID"),
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
        ...(payload.notification_id
          ? { "apns-collapse-id": payload.notification_id }
          : {}),
      },
      body: JSON.stringify({
        aps: {
          alert: { title: payload.title, body: payload.body },
          sound: "default",
        },
        kind: payload.kind,
        target_id: payload.target_id ?? null,
      }),
    },
  );
  if (!result.ok) {
    const detail = await result.json().catch(() => ({})) as { reason?: string };
    if (
      result.status === 410 ||
      ["BadDeviceToken", "Unregistered"].includes(detail.reason ?? "")
    ) {
      throw new ServiceError(
        "PUSH_TOKEN_INVALID",
        "Device token expired",
        410,
        false,
      );
    }
    throw new ServiceError(
      "APNS_ERROR",
      `APNs ${result.status} ${detail.reason ?? ""}`,
      503,
      result.status === 429 || result.status >= 500,
    );
  }
}

export async function sendJpush(
  token: string,
  payload: PushPayload,
  fetcher = fetch,
): Promise<void> {
  const auth = btoa(
    `${requiredEnv("JPUSH_APP_KEY")}:${requiredEnv("JPUSH_MASTER_SECRET")}`,
  );
  const result = await fetcher("https://api.jpush.cn/v3/push", {
    method: "POST",
    signal: AbortSignal.timeout(15_000),
    headers: {
      Authorization: `Basic ${auth}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      platform: "android",
      audience: { registration_id: [token] },
      notification: {
        android: {
          alert: payload.body,
          title: payload.title,
          extras: {
            kind: payload.kind,
            target_id: payload.target_id ?? "",
            notification_id: payload.notification_id ?? "",
          },
        },
      },
      options: { time_to_live: 3600 },
    }),
  });
  if (!result.ok) {
    const detail = await result.json().catch(() => ({})) as {
      error?: { code?: number };
    };
    // JPush 1003 is a parameter error, not proof that a device token is invalid.
    // Even 1011 can mean the SDK has not registered yet; retain the token for later notifications.
    if (detail.error?.code === 1011) {
      throw new ServiceError(
        "JPUSH_NO_TARGET",
        "No registered recipient",
        503,
        true,
      );
    }
    throw new ServiceError(
      "JPUSH_ERROR",
      `JPush ${result.status}`,
      503,
      result.status === 429 || result.status >= 500,
    );
  }
}
