import { type AdminClient } from "./supabase.ts";
import { imageHeader, inspectImage } from "./images.ts";
import { ServiceError } from "./http.ts";

type StorageError = { name: string };
export type ImageBucket = {
  upload(
    path: string,
    bytes: Uint8Array,
    options: { contentType: string; upsert: boolean },
  ): PromiseLike<{ error: StorageError | null }>;
  remove(paths: string[]): PromiseLike<{ error: StorageError | null }>;
};

export function imageBucket(
  client: AdminClient,
  bucket: "avatars" | "evidence",
): ImageBucket {
  return client.storage.from(bucket);
}

export async function uploadAvatar(
  bucket: ImageBucket,
  userId: string,
  file: File,
  now = new Date(),
): Promise<
  { id: string; path: string; source: "avatar"; captured_at: string }
> {
  if (!file.size) {
    throw new ServiceError("IMAGE_REQUIRED", "请选择一张头像图片。");
  }
  if (file.size > 5 * 1024 * 1024) {
    throw new ServiceError(
      "AVATAR_TOO_LARGE",
      "头像图片最多 5 MB，请先缩小图片。",
      413,
    );
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  const header = await imageHeader(bytes, "UTC");
  const inspected = await inspectImage(bytes, "UTC", 512);
  if (
    header.mime !== "image/jpeg" || inspected.metadata.width !== 512 ||
    inspected.metadata.height !== 512
  ) {
    throw new ServiceError(
      "AVATAR_FORMAT",
      "请升级 App 并确认 512×512 的头像预览。",
      400,
    );
  }
  const id = crypto.randomUUID();
  const path = `${userId}/${id}.jpg`;
  const saved = await bucket.upload(path, bytes, {
    contentType: "image/jpeg",
    upsert: false,
  });
  if (saved.error) {
    // A failed response does not establish whether Storage committed. Never
    // compensate by deleting a potentially saved object or the previous avatar.
    throw new ServiceError(
      "AVATAR_UNAVAILABLE",
      "头像保存尚未确认，旧头像仍保留，请稍后重试。",
      503,
      true,
    );
  }
  return { id, path, source: "avatar", captured_at: now.toISOString() };
}
