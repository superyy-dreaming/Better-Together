import { adminClient, authenticate } from "../_shared/supabase.ts";
import {
  boundedBody,
  errorResponse,
  json,
  requirePost,
  ServiceError,
  validUuid,
} from "../_shared/http.ts";
import { imageHeader } from "../_shared/images.ts";
import { imageBucket, uploadAvatar } from "../_shared/storage_images.ts";
import {
  localDate,
  type MediaSource,
  validateCaptureDate,
} from "../_shared/media_rules.ts";
import {
  sha256,
  validateAnalysisImage,
} from "../_shared/analysis_image.ts";

import {parseByokPhoto,pendingByokPhoto} from "../_shared/byok.ts";

export async function handleMedia(request: Request): Promise<Response> {
  const early = requirePost(request);
  if (early) return early;
  try {
    const { user } = await authenticate(request);
    const admin = adminClient();
    const body = await boundedBody(request, 23 * 1024 * 1024);
    let form: FormData;
    try {
      form = await new Response(body, {
        headers: { "content-type": request.headers.get("content-type") ?? "" },
      }).formData();
    } catch {
      throw new ServiceError("FORM_INVALID", "照片上传内容不完整，请重试。");
    }
    const file = form.get("file");
    const source = form.get("source");
    const batchId = form.get("batch_id");
    if (!(file instanceof File) || !file.size) {
      throw new ServiceError("IMAGE_REQUIRED", "请选择一张照片。");
    }
    if (source === "avatar") {
      return json({
        data: await uploadAvatar(imageBucket(admin, "avatars"), user.id, file),
      });
    }
    if (file.size > 20 * 1024 * 1024) {
      throw new ServiceError(
        "IMAGE_TOO_LARGE",
        "每张照片最多 20 MB，请先缩小照片。",
        413,
      );
    }
    if (!["camera", "album", "screenshot"].includes(String(source))) {
      throw new ServiceError(
        "SOURCE_REQUIRED",
        "请选择拍摄、相册或运动截图来源。",
      );
    }
    if (!validUuid(batchId)) {
      throw new ServiceError("BATCH_REQUIRED", "请重新打开打卡页后上传。");
    }
    const photoId = form.get("photo_id");
    const analysisFile = form.get("analysis");
    if (!validUuid(photoId) || !(analysisFile instanceof File)) {
      throw new ServiceError(
        "ANALYSIS_REQUIRED",
        "请使用新版应用重新选择照片。原图与识别用缩图需要一同提交。",
      );
    }
    const { data: profile, error: profileError } = await admin.from("profiles")
      .select("timezone").eq("id", user.id).single();
    if (profileError) {
      throw new ServiceError("PROFILE_REQUIRED", "请先完成个人资料。", 409);
    }
    const { data: membership, error: membershipError } = await admin.from(
      "team_members",
    )
      .select("team_id").eq("user_id", user.id).is("left_at", null)
      .maybeSingle();
    if (membershipError) {
      throw new ServiceError(
        "TEAM_UNAVAILABLE",
        "小队信息暂时无法读取，请稍后重试。",
        503,
        true,
      );
    }
    let timezone: string = profile.timezone;
    if (membership?.team_id) {
      const { data: team, error } = await admin.from("teams").select("timezone")
        .eq("id", membership.team_id).single();
      if (error) {
        throw new ServiceError(
          "TEAM_UNAVAILABLE",
          "小队信息暂时无法读取，请稍后重试。",
          503,
          true,
        );
      }
      timezone = team.timezone;
    }
    const now = new Date();
    const bytes = new Uint8Array(await file.arrayBuffer());
    // Only inspect original headers. Full camera images are never decoded in Edge.
    const header = await imageHeader(bytes, timezone);
    const originalHash = await sha256(bytes);
    const analysis = await validateAnalysisImage(
      new Uint8Array(await analysisFile.arrayBuffer()),
    );
    if (form.get("recognition_receipt")) {
      throw new ServiceError("CLIENT_BYOK_REQUIRED", "请升级 App 后重新选择照片。", 409);
    }
    const encodedResult = form.get("recognition_result");
    let recognition = pendingByokPhoto(photoId);
    if (typeof encodedResult === "string" && encodedResult.length) {
      if (encodedResult.length > 48 * 1024) throw new ServiceError("BYOK_RESULT_INVALID", "识别结果过大。", 422);
      let value: unknown;
      try {value=JSON.parse(encodedResult);} catch {throw new ServiceError("BYOK_RESULT_INVALID", "识别结果不完整。", 422);}
      recognition=parseByokPhoto(value,photoId,String(source));
    }
    if (recognition.status === "rejected") {
      throw new ServiceError("PHOTO_REJECTED", "这张照片已明确不合格，请更换。", 422);
    }
    // OCR unavailability is explicitly pending and cannot prevent an ALL stamp.
    // A known old screenshot is still rejected; ordinary album EXIF is always checked.
    const screenshotDate = recognition.screenshot_date;
    const validated = source === "screenshot" && !screenshotDate
      ? { capturedAt: now, evidence: "screenshot_ocr_pending" }
      : source === "album" && !header.capturedAt
      ? { capturedAt: now, evidence: "exif_date_pending" }
      : validateCaptureDate({
        source: source as MediaSource,
        now,
        timezone,
        exifDate: header.capturedAt,
        screenshotDate,
      });
    const today = localDate(now, timezone);
    const path = `${user.id}/${batchId}/${photoId}.${header.extension}`;
    const { data: existing, error: existingError } = await admin.from("media")
      .select(
        "id,user_id,batch_id,metadata,local_date,team_id,deleted_at,captured_at,source,path,phash",
      )
      .eq("id", photoId).maybeSingle();
    if (existingError) {
      throw new ServiceError(
        "MEDIA_RECORD_UNAVAILABLE",
        "照片记录暂时无法读取，请稍后重试。",
        503,
        true,
      );
    }
    if (existing) {
      if (
        existing.user_id !== user.id || existing.batch_id !== batchId ||
        existing.metadata?.original_sha256 !== originalHash ||
        existing.metadata?.analysis_sha256 !== analysis.sha256 ||
        existing.local_date !== today ||
        existing.team_id !== (membership?.team_id ?? null) ||
        existing.deleted_at || existing.source !== source ||
        existing.path !== path || existing.phash !== analysis.phash
      ) {
        throw new ServiceError(
          "PHOTO_ALREADY_USED",
          "这张照片已关联其他记录，请重新选择照片。",
          409,
        );
      }
      const { data: cached, error } = await admin.from("media_analysis").select(
        "media_id",
      )
        .eq("media_id", photoId).maybeSingle();
      if (error) {
        throw new ServiceError(
          "MEDIA_RECORD_UNAVAILABLE",
          "照片归档状态暂时无法读取，请稍后重试。",
          503,
          true,
        );
      }
      if (cached) {
        return json({
          data: {
            id: existing.id,
            path: existing.path,
            captured_at: existing.captured_at,
            source: existing.source,
          },
        });
      }
      // An interrupted older upload can have a row without its analysis cache.
      // The same immutable identity may repair that cache in the transaction below.
    }
    const bucket = admin.storage.from("evidence");
    let uploadUncertain = false;
    try {
      const original = await bucket.upload(path, bytes, {
        contentType: header.mime,
        upsert: false,
      });
      uploadUncertain = original.error !== null;
    } catch {
      uploadUncertain = true;
    }
    if (uploadUncertain) {
      // A failed response is not proof that Storage did not commit. Read the raw
      // private object, never a transform, and continue only for identical bytes.
      const recovered = await bucket.download(path);
      if (recovered.error || !recovered.data) {
        console.error(JSON.stringify({
          event: "media_archive_recovery_pending",
          media_id: photoId,
        }));
        throw new ServiceError(
          "STORAGE_UNAVAILABLE",
          "照片归档结果暂时无法确认，请保留照片后重试。",
          503,
          true,
        );
      }
      if (
        recovered.data.size !== bytes.length ||
        await sha256(new Uint8Array(await recovered.data.arrayBuffer())) !==
          originalHash
      ) {
        throw new ServiceError(
          "PHOTO_ALREADY_USED",
          "这张照片的上传标识已对应其他内容，请重新选择照片。",
          409,
        );
      }
    }
    const screenshotFields = recognition.fields.filter((f) => f.source === "screenshot");
    // Both rows commit atomically. The RPC locks this photo identity and returns
    // the existing result on replay; it never overwrites verified cache contents.
    const { data, error } = await admin.rpc("register_direct_media", {
      p_media: {
        id: photoId,
        user_id: user.id,
        team_id: membership?.team_id ?? null,
        batch_id: batchId,
        path,
        source,
        captured_at: validated.capturedAt.toISOString(),
        local_date: today,
        phash: analysis.phash,
        metadata: {
          ...header.metadata,
          byok: recognition,
          original_sha256: originalHash,
          analysis_sha256: analysis.sha256,
          analysis_width: analysis.width,
          analysis_height: analysis.height,
          image_mode: "direct",
          date_evidence: validated.evidence,
          screenshot_date: screenshotDate,
          screenshot_fields: screenshotFields,
        },
      },
      p_analysis: {
        data_url: analysis.dataUrl,
        result: null,
        screenshot_date: screenshotDate,
        recognition_status: "pending",
      },
    });
    if (error) {
      // Keep the object on any failed/unknown registration result. Another request
      // may already have committed its reference. Same-identity retry can finish;
      // unrecoverable orphan cleanup requires an independent ownership check.
      console.error(JSON.stringify({
        event: "media_archive_registration_pending",
        media_id: photoId,
        code: error.code,
      }));
      if (error.code === "23505" || error.code === "PT409") {
        throw new ServiceError(
          "PHOTO_ALREADY_USED",
          "这张照片已经用过或上传标识与内容不符，请换一张照片。",
          409,
        );
      }
      if (error.code === "P0001" && error.message.includes("9 张")) {
        throw new ServiceError(
          "PHOTO_LIMIT",
          "每次最多 9 张照片，请移除一张后再试。",
        );
      }
      if (error.code === "PT410") {
        throw new ServiceError(
          "ANALYSIS_EXPIRED",
          "这次上传已过期，请重新选择今天的照片。",
          410,
        );
      }
      throw new ServiceError(
        "MEDIA_RECORD_UNAVAILABLE",
        "照片登记结果暂时无法确认，请保留照片后重试。",
        503,
        true,
      );
    }
    // The transaction enqueues a thumbnail job. Archiving never waits for
    // derivative encoding, signing, or a second object upload.
    return json({ data });
  } catch (error) {
    return errorResponse(error);
  }
}

if (import.meta.main) Deno.serve(handleMedia);
