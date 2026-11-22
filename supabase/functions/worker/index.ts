import { createThumbnail } from "../_shared/thumbnail.ts";
import { type AdminClient, adminClient } from "../_shared/supabase.ts";
import {
  boundedBody,
  checkJobSecret,
  errorResponse,
  json,
  requirePost,
  ServiceError,
} from "../_shared/http.ts";
import { type PushPayload, sendApns, sendJpush } from "../_shared/push.ts";
import { retryTime, safeError } from "../_shared/retry.ts";
import {
  type CleanupMedia,
  cleanupPaths,
  type CleanupPayload,
  cleanupRetryTime,
  removeEvidence,
} from "../_shared/cleanup.ts";

type Job = {
  id: string;
  kind: string;
  payload: { checkin_id?: string; version?: number; report_id?: string };
  attempts: number;
  lease_token: string;
  created_at: string;
};
type PushJob = {
  id: string;
  user_id: string;
  notification_id: string;
  payload: PushPayload & { delivered?: string[] };
  attempts: number;
  lease_token: string;
  created_at: string;
};
type CleanupJob = Omit<Job, "payload"> & { payload: CleanupPayload };
async function rpc(
  client: AdminClient,
  name: string,
  args: Record<string, unknown> = {},
): Promise<unknown> {
  const { data, error } = await client.rpc(name, args);
  if (error) {
    throw new ServiceError(
      "DATABASE_UNAVAILABLE",
      `RPC ${name}: ${error.code}`,
      503,
      true,
    );
  }
  return data;
}

async function runCleanup(
  client: AdminClient,
): Promise<{ completed: number; deferred: number; needs_attention: number }> {
  const jobs = await rpc(client, "claim_jobs", {
    p_kind: "cleanup",
    p_limit: 10,
  }) as CleanupJob[];
  const totals = { completed: 0, deferred: 0, needs_attention: 0 };
  await Promise.all(jobs.map(async (job) => {
    try {
      const { data: media, error } = await client.from("media").select(
        "id,user_id,batch_id,path,analysis_path,thumbnail_path,deleted_at",
      ).eq("id", job.payload.media_id).maybeSingle();
      if (error) {
        throw new ServiceError("DATABASE_UNAVAILABLE", error.code, 503, true);
      }
      if (media) {
        const paths = cleanupPaths(job.payload, media as CleanupMedia);
        await removeEvidence(
          paths,
          (paths) => client.storage.from("evidence").remove(paths),
        );
        const completed = await rpc(client, "complete_media_cleanup", {
          p_media_id: media.id,
          p_job_id: job.id,
          p_lease_token: job.lease_token,
        });
        if (completed !== true) {
          throw new ServiceError(
            "JOB_LEASE_CHANGED",
            "Cleanup lease no longer authorizes completion",
            409,
            true,
          );
        }
      }
      await rpc(client, "finish_job", {
        p_id: job.id,
        p_lease_token: job.lease_token,
      });
      totals.completed++;
    } catch (error) {
      const needsAttention = error instanceof ServiceError &&
        ["CLEANUP_TARGET_INVALID", "CLEANUP_PATH_MISMATCH"].includes(
          error.code,
        );
      const retryAt = needsAttention ? null : cleanupRetryTime(job.attempts);
      await rpc(client, "finish_job", {
        p_id: job.id,
        p_lease_token: job.lease_token,
        p_error: safeError(error),
        p_retry_at: retryAt,
      });
      if (needsAttention) totals.needs_attention++;
      else totals.deferred++;
      console.error(
        JSON.stringify({
          event: "media_cleanup_incomplete",
          job_id: job.id,
          media_id: job.payload.media_id,
          code: safeError(error),
          retry_at: retryAt,
          needs_attention: needsAttention,
        }),
      );
    }
  }));
  return totals;
}

async function processPush(client: AdminClient, job: PushJob): Promise<void> {
  const [
    { data: profile, error: profileError },
    { data: notification, error: notificationError },
    { data: devices, error: devicesError },
  ] = await Promise.all([
    client.from("profiles").select("notification_preferences").eq(
      "id",
      job.user_id,
    ).maybeSingle(),
    client.from("notifications").select("title,body,kind,target_id").eq(
      "id",
      job.notification_id,
    ).eq("user_id", job.user_id).maybeSingle(),
    client.from("devices").select("id,provider,token").eq(
      "user_id",
      job.user_id,
    ),
  ]);
  if (profileError || notificationError || devicesError) {
    throw new ServiceError(
      "DATABASE_UNAVAILABLE",
      "Could not load push recipients",
      503,
      true,
    );
  }
  if (!profile || !notification) return;
  const preferences = profile.notification_preferences as Record<
    string,
    boolean
  >;
  if (preferences.all === false || preferences[notification.kind] === false) {
    return;
  }
  const payload: PushPayload = {
    ...notification,
    notification_id: job.notification_id,
  };
  const delivered = new Set(job.payload.delivered ?? []);
  // Refresh notification body at send time so a poke group contains the latest count.
  for (const device of devices ?? []) {
    const digest = new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(`${device.id}:${device.token}`),
      ),
    );
    const deliveryId = Array.from(
      digest,
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    if (delivered.has(deliveryId)) continue;
    try {
      if (device.provider === "apns") await sendApns(device.token, payload);
      else if (device.provider === "jpush") {
        await sendJpush(device.token, payload);
      }
      delivered.add(deliveryId);
      const { data: saved, error: saveError } = await client.from("push_outbox")
        .update({ payload: { ...job.payload, delivered: [...delivered] } }).eq(
          "id",
          job.id,
        ).eq("lease_token", job.lease_token).eq("status", "processing").select(
          "id",
        ).maybeSingle();
      if (saveError || !saved) {
        throw new ServiceError(
          "PUSH_DELIVERY_RECORD_UNAVAILABLE",
          "Push delivery could not be recorded",
          503,
          true,
        );
      }
    } catch (error) {
      if (
        error instanceof ServiceError && error.code === "PUSH_TOKEN_INVALID"
      ) {
        await client.from("devices").delete().eq("id", device.id).eq(
          "token",
          device.token,
        );
        continue;
      }
      throw error;
    }
  }
}

async function runPush(
  client: AdminClient,
): Promise<{ completed: number; deferred: number; unavailable: number }> {
  const jobs = await rpc(client, "claim_push", { p_limit: 10 }) as PushJob[];
  const totals = { completed: 0, deferred: 0, unavailable: 0 };
  await Promise.all(jobs.map(async (job) => {
    try {
      await processPush(client, job);
      await rpc(client, "finish_push", {
        p_id: job.id,
        p_lease_token: job.lease_token,
      });
      totals.completed++;
    } catch (error) {
      const retryAt = retryTime(error, job.attempts, job.created_at, "UTC");
      await rpc(client, "finish_push", {
        p_id: job.id,
        p_lease_token: job.lease_token,
        p_error: safeError(error),
        p_retry_at: retryAt,
      });
      if (retryAt) totals.deferred++;
      else totals.unavailable++;
      console.error(
        JSON.stringify({
          event: "push_job_incomplete",
          job_id: job.id,
          code: safeError(error),
          retry_at: retryAt,
        }),
      );
    }
  }));
  return totals;
}

async function runThumbnails(client: AdminClient) {
  const jobs = await rpc(client,"claim_jobs",{p_kind:"thumbnail",p_limit:5}) as {id:string;lease_token:string;attempts:number;payload:{media_id:string}}[];
  const totals={completed:0,deferred:0};
  for(const job of jobs) {
    try {
      await createThumbnail(client,job.payload.media_id);
      await rpc(client,"finish_job",{p_id:job.id,p_lease_token:job.lease_token});totals.completed++;
    }catch(error){
      await rpc(client,"finish_job",{p_id:job.id,p_lease_token:job.lease_token,p_error:safeError(error),p_retry_at:cleanupRetryTime(job.attempts)});
      totals.deferred++;
    }
  }
  return totals;
}

export async function handleWorker(request: Request): Promise<Response> {
  const early = requirePost(request);
  if (early) return early;
  try {
    await checkJobSecret(request);
    const bytes = await boundedBody(request, 4096);
    let input: { kind?: string };
    try {
      input = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      throw new ServiceError("INVALID_JSON", "任务请求内容不完整。");
    }
    if (!input || typeof input !== "object") {
      throw new ServiceError("INVALID_JSON", "任务请求内容不完整。");
    }
    const client = adminClient();
    if (input.kind === "thumbnail") return json({data:await runThumbnails(client)});
    if (input.kind === "ai" || input.kind === "report") return json({ data: { skipped: true, reason: "CLIENT_BYOK_REQUIRED" } });
    if (input.kind === "push") return json({ data: await runPush(client) });
    if (input.kind === "cleanup") {
      return json({ data: await runCleanup(client) });
    }
    if (input.kind === "schedule") {
      return json({ data: await rpc(client, "schedule_due") });
    }
    if (input.kind === "all") {
      const schedule = await rpc(client, "schedule_due");
      const [push, cleanup, thumbnail] = await Promise.all([
        runPush(client),
        runCleanup(client),
        runThumbnails(client),
      ]);
      return json({ data: { schedule, push, cleanup, thumbnail } });
    }
    throw new ServiceError(
      "JOB_KIND_INVALID",
      "任务类型需为 push、cleanup、thumbnail、schedule 或 all。",
    );
  } catch (error) {
    return errorResponse(error);
  }
}

if (import.meta.main) Deno.serve(handleWorker);
