import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import jpeg from "npm:jpeg-js@0.4.4";
import { createThumbnail } from "./thumbnail.ts";
import { ServiceError } from "./http.ts";

const owner = "a0000000-0000-4000-8000-000000000001";
const batch = "a0000000-0000-4000-8000-000000000002";
const photo = "a0000000-0000-4000-8000-000000000003";
const path = `${owner}/${batch}/${photo}.thumb.jpg`;
const pixels = new Uint8Array(
  jpeg.encode({ width: 4, height: 4, data: new Uint8Array(64).fill(150) }, 85)
    .data,
);
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
type Row = {
  id: string;
  user_id: string;
  batch_id: string;
  deleted_at: string | null;
  thumbnail_path: string | null;
};
function fixture(
  mode:
    | "normal"
    | "deleted_during_upload"
    | "link_response_lost"
    | "missing_after_upload"
    | "cleanup_response_lost"
    | "upload_response_lost",
) {
  const f = {
    row: {
      id: photo,
      user_id: owner,
      batch_id: batch,
      deleted_at: null,
      thumbnail_path: null,
    } as Row | null,
    bytes: null as Uint8Array | null,
    removed: [] as string[],
    downloads: 0,
    failCleanup: mode === "cleanup_response_lost",
  };
  const result = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { "content-type": "application/json" },
    });
  const client = createClient("https://thumbnail.example.com", "unit-service", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        const url = new URL(
          input instanceof Request ? input.url : String(input),
        );
        const method = init?.method ?? "GET";
        if (
          url.pathname === "/rest/v1/media" && method === "GET"
        ) return result(f.row ? [f.row] : []);
        if (url.pathname === "/rest/v1/media_analysis") {
          return result([{
            data_url: `data:image/jpeg;base64,${
              btoa(String.fromCharCode(...pixels))
            }`,
            expires_at: new Date(Date.now() + 3600_000).toISOString(),
          }]);
        }
        if (url.pathname === "/rest/v1/media" && method === "PATCH") {
          assert(
            url.searchParams.get("deleted_at") === "is.null",
            "link must reject deleted media",
          );
          assert(
            url.searchParams.get("user_id") === `eq.${owner}`,
            "link retains owner",
          );
          assert(
            url.searchParams.get("batch_id") === `eq.${batch}`,
            "link retains batch identity",
          );
          if (f.row && !f.row.deleted_at) f.row.thumbnail_path = path;
          if (mode === "link_response_lost") {
            return result({
              code: "503",
              message: "response lost after commit",
            }, 503);
          }
          return result(f.row && !f.row.deleted_at ? [{ id: photo }] : []);
        }
        if (
          url.pathname.startsWith("/storage/v1/object/evidence/") &&
          method === "POST"
        ) {
          f.bytes = new Uint8Array(
            await new Response(init?.body).arrayBuffer(),
          );
          if (
            mode === "deleted_during_upload" || mode === "cleanup_response_lost"
          ) {
            if (f.row) f.row.deleted_at = "2026-11-21T00:00:00Z";
          }
          if (mode === "missing_after_upload") f.row = null;
          if (mode === "upload_response_lost") {
            return result({
              statusCode: "503",
              error: "Unavailable",
              message: "response lost",
            }, 503);
          }
          return result({ Key: path });
        }
        if (url.pathname.includes("/evidence/") && method === "GET") {
          f.downloads++;
          return new Response(Uint8Array.from(f.bytes ?? []), {
            headers: { "content-type": "image/jpeg" },
          });
        }
        if (
          url.pathname === "/storage/v1/object/evidence" && method === "DELETE"
        ) {
          f.removed.push(
            ...(JSON.parse(String(init?.body)) as { prefixes: string[] })
              .prefixes,
          );
          f.bytes = null;
          if (f.failCleanup) {
            return result({
              statusCode: "503",
              error: "Unavailable",
              message: "response lost",
            }, 503);
          }
          return result([]);
        }
        throw new Error(`Unexpected request ${method} ${url.pathname}`);
      },
    },
  });
  return { f, client };
}
async function pending(run: () => Promise<void>, code: string) {
  try {
    await run();
  } catch (error) {
    assert(
      error instanceof ServiceError && error.code === code,
      `expected ${code}`,
    );
    return;
  }
  throw new Error(`Expected pending ${code}`);
}

Deno.test("thumbnail links an immutable derived object without touching original", async () => {
  const { f, client } = fixture("normal");
  await createThumbnail(client, photo);
  assert(
    f.row?.thumbnail_path === path && f.bytes !== null,
    "thumbnail committed",
  );
  assert(f.removed.length === 0, "no compensating deletion");
});
Deno.test("thumbnail removes only derived pixels when deletion wins upload race", async () => {
  const { f, client } = fixture("deleted_during_upload");
  await createThumbnail(client, photo);
  assert(f.row?.thumbnail_path === null, "deleted media never linked");
  assert(
    f.removed.length === 1 && f.removed[0] === path && f.bytes === null,
    "only exact thumbnail cleaned",
  );
});
Deno.test("thumbnail link response loss preserves committed pixels", async () => {
  const { f, client } = fixture("link_response_lost");
  await pending(() => createThumbnail(client, photo), "THUMBNAIL_LINK_PENDING");
  assert(
    f.row?.thumbnail_path === path && f.bytes !== null,
    "committed link and pixels preserved",
  );
  assert(f.removed.length === 0, "unknown is not deleted");
  await createThumbnail(client, photo);
});
Deno.test("thumbnail missing ownership after upload retains private pixels for reconciliation", async () => {
  const { f, client } = fixture("missing_after_upload");
  await pending(() => createThumbnail(client, photo), "THUMBNAIL_LINK_PENDING");
  assert(
    f.bytes !== null && f.removed.length === 0,
    "missing row gives no deletion authority",
  );
});
Deno.test("thumbnail tombstone retry completes unknown cleanup without re-upload", async () => {
  const { f, client } = fixture("cleanup_response_lost");
  await pending(
    () => createThumbnail(client, photo),
    "THUMBNAIL_CLEANUP_PENDING",
  );
  f.failCleanup = false;
  await createThumbnail(client, photo);
  assert(
    f.removed.length === 2 && f.removed.every((value) => value === path),
    "idempotent cleanup retries exact derived path",
  );
});
Deno.test("thumbnail upload response loss verifies immutable bytes before linking", async () => {
  const { f, client } = fixture("upload_response_lost");
  await createThumbnail(client, photo);
  assert(
    f.downloads === 1 && f.row?.thumbnail_path === path,
    "unknown upload reconciled by bytes",
  );
  assert(f.removed.length === 0, "saved image retained");
});
