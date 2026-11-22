import { handleApi } from "../api/index.ts";

Deno.test("committed invite denials propagate as errors instead of successful joins", async () => {
  const fetchBefore = globalThis.fetch;
  const names = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"];
  const before = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://db.example.test");
  Deno.env.set(names[1], "unit-anon");
  Deno.env.set(names[2], "unit-service");
  try {
    for (const status of [400, 429]) {
      globalThis.fetch = (input: string | URL | Request) => {
        const url = new URL(input instanceof Request ? input.url : String(input));
        const body = url.pathname === "/auth/v1/user"
          ? { id: "16000000-0000-4000-8000-000000000001", aud: "authenticated" }
          : { error: { code: status === 429 ? "INVITE_RATE_LIMIT" : "INVITE_INVALID", message: "请核对邀请码", status } };
        return Promise.resolve(new Response(JSON.stringify(body), {
          headers: { "Content-Type": "application/json" },
        }));
      };
      const response = await handleApi(new Request("https://edge.example/api", {
        method: "POST", headers: { Authorization: "Bearer test-token" },
        body: JSON.stringify({ action: "join_team", token: "ABCD23EF" }),
      }));
      const body = await response.json();
      if (response.status !== status || !body.error || body.data) {
        throw new Error("Invite denial was not propagated");
      }
    }
  } finally {
    globalThis.fetch = fetchBefore;
    names.forEach((name, i) => before[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, before[i]!));
  }
});
