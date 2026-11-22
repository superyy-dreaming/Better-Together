import { authenticate } from "../_shared/supabase.ts";
import { errorResponse, requirePost, ServiceError } from "../_shared/http.ts";

/** Compatibility tombstone: never parses photos, keys or provider configuration. */
export async function handleRecognize(request: Request): Promise<Response> {
  const early=requirePost(request); if (early) return early;
  try {
    await authenticate(request);
    throw new ServiceError("CLIENT_BYOK_REQUIRED", "请升级 App 并在本机配置 AI。可先按 ALL 盖章，纪要待补。", 503, false);
  } catch (error) { return errorResponse(error); }
}
if (import.meta.main) Deno.serve(handleRecognize);
