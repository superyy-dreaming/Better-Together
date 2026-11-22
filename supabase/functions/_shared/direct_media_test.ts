import jpeg from "npm:jpeg-js@0.4.4";
import { handleMedia } from "../media/index.ts";
import { sha256 } from "./analysis_image.ts";
import { pendingByokPhoto, type ByokPhoto } from "./byok.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const owner = "a0000000-0000-4000-8000-000000000001";
const batch = "a0000000-0000-4000-8000-000000000002";
const photo = "a0000000-0000-4000-8000-000000000003";
const bytes = new Uint8Array(
  jpeg.encode({
    width: 16,
    height: 16,
    data: new Uint8Array(16 * 16 * 4).fill(150),
  }, 85).data,
);
type Row = Record<string, unknown>;
type Fixture = {
  media: Row | null;
  analysis: Row | null;
  uploads: string[];
  removed: string[];
  failCache: boolean;
  commitThenError: boolean;
  storageCommitThenError: boolean;
  failDownload: boolean;
  objectBytes: Uint8Array | null;
  downloads: number;
  duplicate: boolean;
  calls: string[];
};
async function withMedia(run: (fixture: Fixture) => Promise<void>) {
  const oldFetch = globalThis.fetch;
  const values = {
    SUPABASE_URL: "https://db.example.com",
    SUPABASE_ANON_KEY: "unit-anon",
    SUPABASE_SERVICE_ROLE_KEY: "unit-service",
    JOB_SECRET: "synthetic-receipt-secret",
  };
  const old = new Map(Object.keys(values).map((k) => [k, Deno.env.get(k)]));
  for (const [k, v] of Object.entries(values)) Deno.env.set(k, v);
  const f: Fixture = {
    media: null,
    analysis: null,
    uploads: [],
    removed: [],
    failCache: false,
    commitThenError: false,
    storageCommitThenError: false,
    failDownload: false,
    objectBytes: null,
    downloads: 0,
    duplicate: false,
    calls: [],
  };
  globalThis.fetch =
    (async (input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const method = init?.method ?? "GET";
      f.calls.push(url.pathname);
      const result = (data: unknown, status = 200) =>
        Promise.resolve(
          new Response(JSON.stringify(data), {
            status,
            headers: { "content-type": "application/json" },
          }),
        );
      if (url.pathname === "/auth/v1/user") {
        return result({
          id: owner,
          aud: "authenticated",
          role: "authenticated",
        });
      }
      if (url.pathname === "/rest/v1/profiles") {
        return result({ timezone: "Asia/Shanghai" });
      }
      if (url.pathname === "/rest/v1/team_members") return result([]);
      if (url.pathname === "/rest/v1/media" && method === "GET") {
        return result(f.media ? [f.media] : []);
      }
      if (url.pathname === "/rest/v1/media_analysis" && method === "GET") {
        return result(f.analysis ? [f.analysis] : []);
      }
      if (url.pathname === "/rest/v1/rpc/register_direct_media") {
        const { p_media: media, p_analysis: analysis } = JSON.parse(
          String(init?.body),
        ) as { p_media: Row; p_analysis: Row };
        if (f.duplicate) {
          return result({ code: "23505", message: "duplicate" }, 409);
        }
        if (f.media) {
          const current = f.media.metadata as Row;
          const incoming = media.metadata as Row;
          if (
            [
              "user_id",
              "batch_id",
              "source",
              "path",
              "team_id",
              "phash",
              "local_date",
            ].some((key) => f.media?.[key] !== media[key]) ||
            current.original_sha256 !== incoming.original_sha256 ||
            current.analysis_sha256 !== incoming.analysis_sha256
          ) {
            return result({ code: "PT409", message: "identity conflict" }, 409);
          }
        }
        // The real RPC is transactional: a failed cache insert exposes neither row.
        if (f.failCache) {
          return result({ code: "XX000", message: "private failure" }, 503);
        }
        f.media ??= { ...media, analysis_path: null };
        f.analysis ??= {
          ...analysis,
          media_id: media.id,
          expires_at: "fixed-original-deadline",
        };
        if (f.commitThenError) {
          return result(
            { code: "503", message: "response lost after commit" },
            503,
          );
        }
        return result({
          id: f.media.id,
          path: f.media.path,
          captured_at: f.media.captured_at,
          source: f.media.source,
        });
      }
      if (
        (url.pathname.startsWith(
          "/storage/v1/object/authenticated/evidence/",
        ) ||
          url.pathname.startsWith("/storage/v1/object/evidence/")) &&
        method === "GET"
      ) {
        f.downloads++;
        if (f.failDownload || !f.objectBytes) {
          return result({
            statusCode: "503",
            error: "Unavailable",
            message: "read unavailable",
          }, 503);
        }
        return new Response(Uint8Array.from(f.objectBytes), {
          headers: { "content-type": "image/jpeg" },
        });
      }
      if (
        url.pathname.startsWith("/storage/v1/object/evidence/") &&
        method === "POST"
      ) {
        f.uploads.push(url.pathname);
        const incomingBytes = new Uint8Array(
          await new Response(init?.body).arrayBuffer(),
        );
        if (f.objectBytes) {
          return result({
            statusCode: "409",
            error: "Duplicate",
            message: "object exists",
          }, 409);
        }
        f.objectBytes = incomingBytes;
        if (f.storageCommitThenError) {
          return result({
            statusCode: "503",
            error: "Unavailable",
            message: "response lost",
          }, 503);
        }
        return result({ Key: "saved" });
      }
      if (
        url.pathname === "/storage/v1/object/evidence" && method === "DELETE"
      ) {
        f.removed.push(...JSON.parse(String(init?.body)).prefixes);
        f.objectBytes = null;
        return result([]);
      }
      throw new Error("Unexpected external request: " + url.pathname);
    }) as typeof fetch;
  try {
    await run(f);
  } finally {
    globalThis.fetch = oldFetch;
    for (const [k, v] of old) {
      v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
    }
  }
}
function request(
  source = "camera",
  result?: ByokPhoto,
  original = bytes,
  analysis = bytes,
) {
  const form = new FormData();
  form.set(
    "file",
    new File([Uint8Array.from(original)], "original.jpg", {
      type: "image/jpeg",
    }),
  );
  form.set(
    "analysis",
    new File([Uint8Array.from(analysis)], "analysis.jpg", {
      type: "image/jpeg",
    }),
  );
  form.set("source", source);
  form.set("photo_id", photo);
  form.set("batch_id", batch);
  if (result) form.set("recognition_result", JSON.stringify(result));
  return new Request("https://db.example.com/functions/v1/media", {
    method: "POST",
    headers: { authorization: "Bearer unit-user" },
    body: form,
  });
}
Deno.test("direct media archives only the original and keeps retry image outside Storage", () =>
  withMedia(async (f) => {
    const response = await handleMedia(request());
    assert(response.status === 200, await response.text());
    assert(
      f.uploads.length === 1 && !f.uploads[0].includes("analysis"),
      "Archiving waits only for the original; thumbnail job is separate",
    );
    assert(
      !f.calls.some((x) =>
        x.includes("render") || x.includes("/functions/v1/recognize")
      ),
      "Archive invoked Transform or AI",
    );
    assert(
      f.analysis?.recognition_status === "pending" &&
        typeof f.analysis?.data_url === "string",
      "Missing explicit pending retry cache",
    );
    assert(f.media?.analysis_path === null, "Storage analysis path retained");
    const metadata = f.media?.metadata as Row;
    assert(
      metadata.original_sha256 === await sha256(bytes),
      "Original SHA was not computed by server",
    );
    assert(typeof f.media?.phash === "string", "Server pHash missing");
    const again = await handleMedia(request());
    assert(
      again.status === 200 && f.uploads.length === 1,
      "Same upload retry is not idempotent",
    );
  }));
Deno.test("unavailable screenshot OCR does not block archival and is explicitly unverified", () =>
  withMedia(async (f) => {
    const response = await handleMedia(request("screenshot"));
    assert(response.status === 200, await response.text());
    assert(
      (f.media?.metadata as Row).date_evidence === "screenshot_ocr_pending",
      "Invented verified screenshot date",
    );
  }));
Deno.test("album with unknown EXIF remains explicitly unverified and can stamp", () =>
  withMedia(async(f)=>{
    const response=await handleMedia(request("album"));
    assert(response.status===200,"Unknown EXIF blocked archive");
    assert((f.media?.metadata as Row).date_evidence==="exif_date_pending","Invented EXIF date");
  }));
Deno.test("known old screenshot is rejected and malformed client provenance cannot inject a memo", () =>
  withMedia(async (f) => {
    const result = {...pendingByokPhoto(photo),screenshot_date:"2020-01-01"};
    const response=await handleMedia(request("screenshot",result));
    assert(response.status>=400 && f.uploads.length===0,"Known old date accepted");
    const altered=await handleMedia(request("screenshot",{...result,origin:"forged"} as unknown as ByokPhoto));
    assert(altered.status>=400 && f.uploads.length===0,"Invalid provenance accepted");
  }));
Deno.test("duplicate original or perceptual hash fails without destructive compensation", () =>
  withMedia(async (f) => {
    f.duplicate = true;
    const response = await handleMedia(request());
    assert(
      response.status === 409 &&
        (await response.json()).error.code === "PHOTO_ALREADY_USED",
      "Duplicate accepted",
    );
    assert(
      f.removed.length === 0 && f.media === null && f.objectBytes !== null,
      "Duplicate failure deleted a possibly referenced object",
    );
  }));
Deno.test("cache transaction failure exposes no partial row and the same upload recovers", () =>
  withMedia(async (f) => {
    f.failCache = true;
    const first = await handleMedia(request());
    assert(
      first.status === 503 && f.media === null && f.analysis === null,
      "Failed cache exposed a partial archive",
    );
    assert(
      f.objectBytes !== null && f.removed.length === 0,
      "Unknown archive was destroyed",
    );
    f.failCache = false;
    const second = await handleMedia(request());
    assert(
      second.status === 200 && f.media !== null && f.analysis !== null,
      "Retry did not complete both records",
    );
    assert(f.removed.length === 0, "Recovery used destructive compensation");
  }));
Deno.test("lost database commit response preserves original and retry returns the committed result", () =>
  withMedia(async (f) => {
    f.commitThenError = true;
    const first = await handleMedia(request());
    assert(
      first.status === 503 && f.media !== null && f.analysis !== null,
      "Fault did not simulate an unknown commit",
    );
    assert(
      f.objectBytes !== null && f.removed.length === 0,
      "Committed original was deleted",
    );
    f.commitThenError = false;
    const second = await handleMedia(request());
    assert(
      second.status === 200 && f.uploads.length === 1,
      "Committed retry uploaded again",
    );
  }));
Deno.test("lost Storage response recovers by verifying the exact raw original", () =>
  withMedia(async (f) => {
    f.storageCommitThenError = true;
    const response = await handleMedia(request());
    assert(
      response.status === 200 && f.media !== null && f.analysis !== null,
      "Identical stored object was not recovered",
    );
    assert(
      f.downloads === 1,
      "Recovery did not read raw private object",
    );
    assert(
      !f.calls.some((path) => path.includes("render")) &&
        f.removed.length === 0,
      "Recovery transformed or deleted the object",
    );
  }));
Deno.test("unobservable Storage commit remains recoverable after reads return", () =>
  withMedia(async (f) => {
    f.storageCommitThenError = true;
    f.failDownload = true;
    const first = await handleMedia(request());
    assert(
      first.status === 503 && f.objectBytes !== null && f.media === null,
      "Unknown Storage result was not retained",
    );
    f.failDownload = false;
    const second = await handleMedia(request());
    assert(
      second.status === 200 && f.media !== null,
      "Storage recovery could not exit after dependency recovery",
    );
    assert(f.removed.length === 0, "Uncertain object was deleted");
  }));
Deno.test("an interrupted old media row repairs its cache without changing the identity", () =>
  withMedia(async (f) => {
    assert((await handleMedia(request())).status === 200, "Setup failed");
    const stored = JSON.stringify(f.media);
    f.analysis = null;
    const recovered = await handleMedia(request());
    assert(
      recovered.status === 200 && f.analysis !== null,
      "Missing cache did not recover",
    );
    assert(
      JSON.stringify(f.media) === stored && f.removed.length === 0,
      "Cache repair replaced the media record",
    );
  }));
Deno.test("concurrent identical photo requests converge on one archive and one cache", () =>
  withMedia(async (f) => {
    const responses = await Promise.all([
      handleMedia(request()),
      handleMedia(request()),
    ]);
    assert(
      responses.every((response) => response.status === 200),
      "Concurrent same-identity retry failed",
    );
    assert(
      f.media !== null && f.analysis !== null && f.objectBytes !== null &&
        f.removed.length === 0,
      "Concurrent upload lost a record or original",
    );
    assert(
      await sha256(f.objectBytes) === await sha256(bytes),
      "Stored bytes changed",
    );
  }));
Deno.test("concurrent same photo ID with different original bytes cannot overwrite the winner", () =>
  withMedia(async (f) => {
    const changed = new Uint8Array([...bytes, 1]);
    const responses = await Promise.all([
      handleMedia(request()),
      handleMedia(request("camera", undefined, changed)),
    ]);
    assert(
      responses.filter((response) => response.status === 200).length === 1 &&
        responses.filter((response) => response.status === 409).length === 1,
      "Conflicting bytes were not isolated",
    );
    assert(
      f.objectBytes !== null && f.media !== null && f.removed.length === 0,
      "Conflict destroyed the winner",
    );
    assert(
      (f.media.metadata as Row).original_sha256 === await sha256(f.objectBytes),
      "Stored object and row diverged",
    );
  }));
Deno.test("same original with a different analysis image cannot replace verified cache", () =>
  withMedia(async (f) => {
    assert((await handleMedia(request())).status === 200, "Setup failed");
    const originalCache = JSON.stringify(f.analysis);
    const changedAnalysis = new Uint8Array(
      jpeg.encode({
        width: 16,
        height: 16,
        data: new Uint8Array(16 * 16 * 4).fill(90),
      }, 85).data,
    );
    const conflict = await handleMedia(
      request("camera", undefined, bytes, changedAnalysis),
    );
    assert(
      conflict.status === 409 && JSON.stringify(f.analysis) === originalCache &&
        f.removed.length === 0,
      "Analysis conflict replaced a completed cache",
    );
  }));
