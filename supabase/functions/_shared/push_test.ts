import { apnsToken, sendApns, sendJpush } from "./push.ts";
import { ServiceError } from "./http.ts";

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
function decode(part: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(
    atob(part.replaceAll("-", "+").replaceAll("_", "/")),
    (c) => c.charCodeAt(0),
  );
}

Deno.test("APNs ES256 token is locally verifiable and requests contain native alert headers", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const privateKey = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  const settings: Record<string, string> = {
    APNS_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${
      btoa(String.fromCharCode(...privateKey))
    }\n-----END PRIVATE KEY-----`,
    APNS_KEY_ID: "TESTKEY123",
    APNS_TEAM_ID: "TESTTEAM12",
    APNS_BUNDLE_ID: "test.better.together",
    APNS_ENVIRONMENT: "sandbox",
  };
  const previous = new Map(
    Object.keys(settings).map((key) => [key, Deno.env.get(key)]),
  );
  try {
    for (const [key, value] of Object.entries(settings)) {
      Deno.env.set(key, value);
    }
    const token = await apnsToken();
    const [header, payload, signature] = token.split(".");
    assert(
      await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        keys.publicKey,
        decode(signature),
        new TextEncoder().encode(`${header}.${payload}`),
      ),
      "Invalid signature",
    );
    assert(
      JSON.parse(new TextDecoder().decode(decode(header))).alg === "ES256",
      "Wrong algorithm",
    );
    const fetcher: typeof fetch = (url, init) => {
      assert(
        String(url).startsWith("https://api.sandbox.push.apple.com/3/device/"),
        "Wrong APNs host",
      );
      assert(
        new Headers(init?.headers).get("apns-push-type") === "alert",
        "Wrong push type",
      );
      assert(
        new Headers(init?.headers).get("apns-collapse-id") === "notification-1",
        "Missing aggregate id",
      );
      return Promise.resolve(new Response("{}", { status: 410 }));
    };
    try {
      await sendApns("device-token", {
        title: "test",
        body: "test",
        kind: "poke",
        notification_id: "notification-1",
      }, fetcher);
      throw new Error("Accepted invalid token");
    } catch (error) {
      assert(
        error instanceof ServiceError && error.code === "PUSH_TOKEN_INVALID",
        "Invalid token not classified",
      );
    }
  } finally {
    for (const [key, value] of previous) {
      value === undefined ? Deno.env.delete(key) : Deno.env.set(key, value);
    }
  }
});
Deno.test("JPush parameter errors do not delete valid device registrations", async () => {
  const keys = ["JPUSH_APP_KEY", "JPUSH_MASTER_SECRET"];
  const previous = keys.map((key) => Deno.env.get(key));
  try {
    keys.forEach((key) => Deno.env.set(key, "test-only"));
    for (const code of [1003, 1011]) {
      const fetcher: typeof fetch = () =>
        Promise.resolve(
          new Response(JSON.stringify({ error: { code } }), { status: 400 }),
        );
      try {
        await sendJpush("registration-id", {
          title: "test",
          body: "test",
          kind: "poke",
        }, fetcher);
        throw new Error("Accepted API error");
      } catch (error) {
        assert(
          error instanceof ServiceError && error.code !== "PUSH_TOKEN_INVALID",
          "Parameter error invalidated token",
        );
      }
    }
  } finally {
    keys.forEach((key, index) =>
      previous[index] === undefined
        ? Deno.env.delete(key)
        : Deno.env.set(key, previous[index]!)
    );
  }
});
