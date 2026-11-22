import { handleMedia } from "../media/index.ts";
import { handleWorker } from "../worker/index.ts";
import { boundedBody, ServiceError } from "./http.ts";

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
Deno.test("media rejects unauthenticated uploads before parsing photos", async () => {
  const result = await handleMedia(
    new Request("https://local/media", { method: "POST", body: "not a photo" }),
  );
  assert(
    result.status === 401,
    "Unauthenticated request must not reach storage",
  );
});
Deno.test("chunked bodies cannot bypass size limits with absent content-length", async () => {
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(12));
      controller.close();
    },
  });
  const request = new Request("https://local", {
    method: "POST",
    body: stream,
  });
  try {
    await boundedBody(request, 8);
    throw new Error("Accepted oversized chunked body");
  } catch (error) {
    assert(
      error instanceof ServiceError && error.status === 413,
      "Wrong body limit response",
    );
  }
});
Deno.test("worker requires secret before accessing database and permits preflight", async () => {
  const previous = Deno.env.get("JOB_SECRET");
  Deno.env.set("JOB_SECRET", "unit-test-only");
  try {
    const unauthorized = await handleWorker(
      new Request("https://local/worker", {
        method: "POST",
        body: '{"kind":"all"}',
      }),
    );
    assert(unauthorized.status === 401, "Worker accepted missing secret");
    const preflight = await handleWorker(
      new Request("https://local/worker", { method: "OPTIONS" }),
    );
    assert(preflight.status === 204, "Worker preflight invalid");
    const method = await handleWorker(new Request("https://local/worker"));
    assert(method.status === 405, "Worker accepted GET");
  } finally {
    previous === undefined
      ? Deno.env.delete("JOB_SECRET")
      : Deno.env.set("JOB_SECRET", previous);
  }
});
