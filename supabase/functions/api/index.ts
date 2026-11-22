import { adminClient, authenticate } from "../_shared/supabase.ts";
import {
  boundedBody,
  errorResponse,
  json,
  requirePost,
  ServiceError,
} from "../_shared/http.ts";
import { databaseError, isAllowedAction } from "../_shared/domain.ts";

type RecordValue = Record<string, unknown>;
type Photo = { id: string; url: string; analysis_path?: string };
type Checkin = { photos: Photo[] };
type Profile = { id: string; avatar_url?: string | null };
type Snapshot = {
  profile: Profile;
  team: { members: Profile[] } | null;
  checkins: Checkin[];
};

async function removeOwnedObjects(
  bucket: "avatars" | "evidence",
  prefix: string,
): Promise<void> {
  const storage = adminClient().storage.from(bucket);
  for (;;) {
    const { data: entries, error } = await storage.list(prefix, {
      limit: 1000,
    });
    if (error) {
      throw new ServiceError(
        "DELETE_RETRY",
        "媒体清单暂时无法读取，请稍后重试。",
        503,
      );
    }
    if (!entries?.length) return;
    for (const entry of entries.filter((entry) => !entry.id)) {
      await removeOwnedObjects(bucket, `${prefix}/${entry.name}`);
    }
    const paths = entries.filter((entry) => entry.id).map((entry) =>
      `${prefix}/${entry.name}`
    );
    if (paths.length) {
      const { error } = await storage.remove(paths);
      if (error) {
        throw new ServiceError(
          "DELETE_RETRY",
          "媒体尚未清理，请稍后重试。",
          503,
        );
      }
    }
  }
}

async function signedSnapshot(snapshot: Snapshot) {
  const admin = adminClient();
  const photos = snapshot.checkins.flatMap((c) => c.photos);
  const paths = [...new Set(photos.map((p) => p.url).filter(Boolean))];
  if (paths.length) {
    const { data, error } = await admin.storage.from("evidence")
      .createSignedUrls(paths, 300);
    if (error) {
      throw new ServiceError(
        "MEDIA_UNAVAILABLE",
        "照片暂时无法读取，请稍后刷新。",
        503,
      );
    }
    const urls = new Map(data.map((item) => [item.path, item.signedUrl]));
    for (const photo of photos) {
      photo.url = urls.get(photo.url) ?? "";
      delete photo.analysis_path;
    }
  }
  for (const profile of [snapshot.profile, ...(snapshot.team?.members ?? [])]) {
    if (profile.avatar_url && !profile.avatar_url.startsWith("preset:")) {
      const { data, error } = await admin.storage.from("avatars")
        .createSignedUrl(profile.avatar_url, 300);
      if (error) {
        throw new ServiceError(
          "AVATAR_UNAVAILABLE",
          "头像暂时无法读取，请稍后刷新。",
          503,
        );
      }
      profile.avatar_url = data.signedUrl;
    }
  }
  return snapshot;
}

export async function handleApi(request: Request): Promise<Response> {
  const early = requirePost(request);
  if (early) return early;
  try {
    const { client, user } = await authenticate(request);
    const bytes = await boundedBody(request, 128 * 1024);
    let body: RecordValue;
    try {
      body = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      throw new ServiceError("INVALID_JSON", "请求内容不完整，请重试。");
    }
    if (!body || typeof body !== "object" || !isAllowedAction(body.action)) {
      throw new ServiceError("UNKNOWN_ACTION", "不支持的操作。");
    }
    const { action, ...args } = body;
    if (["get_ai_settings", "save_ai_settings", "delete_ai_settings", "test_ai_settings"].includes(action)) {
      throw new ServiceError("CLIENT_BYOK_REQUIRED", "请升级 App，在本机设置 AI。服务器不再保存密钥或转发识别。", 409);
    }
    if (Object.hasOwn(args, "api_key") || Object.hasOwn(args, "secret")) {
      throw new ServiceError("CREDENTIAL_PAYLOAD_REJECTED", "密钥只能保存在设备安全存储。", 422);
    }
    if (["ai_context", "save_byok_photo", "report_ai_context", "save_byok_report"].includes(action)) {
      const { data, error } = await client.rpc(action, { p_args: args });
      if (error) {
        const e=databaseError(error.code,error.message);
        throw new ServiceError(e.code,e.message,e.status);
      }
      return json({data});
    }
    if (
      ["bootstrap_v2", "read_page", "get_checkin", "get_plan", "media_urls"]
        .includes(action)
    ) {
      const started = performance.now();
      const rpc = action === "media_urls" ? "media_access" : action;
      const params = action === "read_page"
        ? { p_args: args }
        : ["get_checkin", "get_plan"].includes(action)
        ? { p_id: args.id }
        : action === "media_urls"
        ? { p_refs: args.refs }
        : undefined;
      const { data, error } = await client.rpc(rpc, params);
      if (error) {
        const e = databaseError(error.code, error.message);
        throw new ServiceError(e.code, e.message, e.status);
      }
      const rpcMs = Math.round(performance.now() - started);
      if (action === "media_urls") {
        const rows = data as {
          ref: string;
          variant: string;
          bucket: string;
          path: string | null;
          allowed: boolean;
        }[];
        const admin = adminClient();
        const signed = new Map<string, string>();
        await Promise.all(["evidence", "avatars"].map(async (bucket) => {
          const paths = [
            ...new Set(
              rows.filter((r) => r.allowed && r.bucket === bucket).map((r) =>
                r.path!
              ),
            ),
          ];
          if (!paths.length) return;
          const result = await admin.storage.from(bucket).createSignedUrls(
            paths,
            300,
          );
          if (result.error) {
            throw new ServiceError(
              "MEDIA_UNAVAILABLE",
              "图片暂时无法读取，请点击重试。",
              503,
            );
          }
          for (const item of result.data ?? []) {
            if (item.path && item.signedUrl) {
              signed.set(`${bucket}/${item.path}`, item.signedUrl);
            }
          }
        }));
        return json({
          data: {
            items: rows.map((row) => ({
              ref: row.ref,
              variant: row.variant,
              allowed: row.allowed,
              url: row.allowed
                ? signed.get(`${row.bucket}/${row.path}`) ?? null
                : null,
              expires_at: new Date(Date.now() + 300_000).toISOString(),
            })),
          },
        });
      }
      const response = json({ data });
      response.headers.set("Server-Timing", `db;dur=${rpcMs}`);
      console.log(
        JSON.stringify({ event: "scoped_read", action, rpc_ms: rpcMs }),
      );
      return response;
    }
    if (action === "bootstrap") {
      const { data, error } = await client.rpc("bootstrap");
      if (error) {
        const e = databaseError(error.code, error.message);
        throw new ServiceError(e.code, e.message, e.status);
      }
      return json({ data: await signedSnapshot(data as Snapshot) });
    }
    if (
      action === "save_profile" && typeof args.avatar_url === "string" &&
      !args.avatar_url.startsWith("preset:") &&
      !args.avatar_url.startsWith(`${user.id}/`)
    ) throw new ServiceError("AVATAR_OWNER", "请选择自己的头像。");
    if (action === "delete_account") {
      if (args.confirmation !== "DELETE") {
        throw new ServiceError(
          "CONFIRM_REQUIRED",
          "请确认删除账号及个人数据。",
        );
      }
      const admin = adminClient();
      const { error: cleanupError } = await client.rpc(
        "prepare_account_deletion",
      );
      if (cleanupError) {
        throw new ServiceError(
          "DELETE_RETRY",
          "账号删除尚未开始，请稍后重试。",
          503,
        );
      }
      for (let offset = 0;; offset += 500) {
        const { data: media, error: mediaError } = await admin.from("media")
          .select("path,analysis_path,thumbnail_path").eq("user_id", user.id)
          .order("id")
          .range(offset, offset + 499);
        if (mediaError) {
          throw new ServiceError(
            "DELETE_UNAVAILABLE",
            "数据清单暂时无法读取，请稍后重试。",
            503,
          );
        }
        const evidence = (media ?? []).flatMap((
          m: {
            path: string;
            analysis_path: string | null;
            thumbnail_path: string | null;
          },
        ) => [
          m.path,
          ...(m.analysis_path ? [m.analysis_path] : []),
          ...(m.thumbnail_path ? [m.thumbnail_path] : []),
        ]);
        for (let i = 0; i < evidence.length; i += 100) {
          const { error } = await admin.storage.from("evidence").remove(
            evidence.slice(i, i + 100),
          );
          if (error) {
            throw new ServiceError(
              "DELETE_RETRY",
              "部分照片尚未清理，请稍后再次删除账号。",
              503,
            );
          }
        }
        if ((media?.length ?? 0) < 500) break;
      }
      await removeOwnedObjects("evidence", user.id);
      await removeOwnedObjects("avatars", user.id);
      const { error } = await admin.auth.admin.deleteUser(user.id);
      if (error) {
        throw new ServiceError(
          "DELETE_RETRY",
          "账号尚未删除，请稍后再次尝试。",
          503,
        );
      }
      return json({ data: { deleted: true } });
    }
    const { data, error } = await client.rpc("app_action", {
      p_action: action,
      p_args: args,
    });
    if (error) {
      const e = databaseError(error.code, error.message);
      if (e.status === 503) {
        console.error(
          JSON.stringify({ event: "database_error", action, code: error.code }),
        );
      }
      throw new ServiceError(e.code, e.message, e.status);
    }
    // Invitation denials commit their attempt counter in the RPC transaction.
    // Propagate the explicit envelope only after that transaction has finished.
    if ((action === "join_team" || action === "create_invite") && data?.error) {
      const denial = data.error;
      throw new ServiceError(denial.code, denial.message, denial.status);
    }
    if (action === "create_invite" && data?.token) {
      const host = Deno.env.get("APP_LINK_HOST");
      if (host) data.url = `https://${host}/invite/${data.token}`;
    }
    if (args.response_version === 2 && data && typeof data === "object") {
      const result = data as RecordValue;
      if(action === "save_profile") {
        try {const profile=await client.rpc("get_profile");if(!profile.error) result.updated_profile=profile.data;}
        catch(_){result.refresh_pending=true;}
      }
      const ids = Array.isArray(result.checkin_ids)
        ? result.checkin_ids
        : typeof args.checkin_id === "string"
        ? [args.checkin_id]
        : [];
      if (ids.length) {
        try {
        const records = await Promise.all(
          ids.slice(0, 9).map(async (id) => {
            const read = await client.rpc("get_checkin", { p_id: id });
            return read.error ? null : read.data;
          }),
        );
        result.updated_checkins = records.filter(Boolean);
        } catch (_) {
          // The write committed. A dependent read failure is a refresh issue.
          result.refresh_pending = true;
        }
      }
    }
    return json({ data });
  } catch (error) {
    return errorResponse(error);
  }
}
if (import.meta.main) Deno.serve(handleApi);
